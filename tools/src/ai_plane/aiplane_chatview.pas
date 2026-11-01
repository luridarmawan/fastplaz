unit aiplane_chatview;

{
  Conversation view for AI Plane: a scroll box with one owner drawn paint box.

  Every message is a TAIChatItem (user, assistant, thinking, tool call, plan,
  permission, error, info). Items are laid out once per width and only the
  item that changed is measured again, so streaming stays cheap. Text inside
  ``` fences is drawn in a monospace font on a shaded block.

  Tool, thinking and plan items fold to their header; a click on the header
  toggles them. Permission items draw their options as buttons and raise
  OnButtonClick. Text is copied through the context menu.

  LCL only, no IDEIntf: the IDE window and the tester app both use it.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, Controls, Forms, Graphics, ExtCtrls, Menus,
  Clipbrd, LCLType, LCLIntf, aiplane_types;

type
  TAIChatItemKind = (cikUser, cikAssistant, cikThinking, cikTool, cikPlan,
    cikPermission, cikError, cikInfo);

  TAIChatButton = record
    Id: string;
    Caption: string;
    Kind: string;
    Rect: TRect;  // in paint box coordinates, set while painting
  end;

  TAIChatSegment = record
    IsCode: boolean;
    Text: string;
    Height: integer;
  end;

  { TAIChatItem }

  TAIChatItem = class
  public
    Kind: TAIChatItemKind;
    Key: string;          // tool call id or permission key
    Title: string;
    Text: string;
    Path: string;
    Status: TAIToolStatus;
    Collapsed: boolean;
    Answer: string;       // permission: caption of the chosen option
    Buttons: array of TAIChatButton;
    // layout
    Top: integer;
    Height: integer;
    HeaderHeight: integer;
    ButtonsHeight: integer;
    Segments: array of TAIChatSegment;
    Valid: boolean;
    function Collapsible: boolean;
    function HeaderText: string;
  end;

  TAIChatButtonEvent = procedure(Sender: TObject; AItem: TAIChatItem;
    const AButtonId: string) of object;

  { TAIChatView }

  TAIChatView = class(TScrollBox)
  private
    FBox: TPaintBox;
    FItems: TObjectList;
    FMeasure: TBitmap;
    FCodeFont: TFont;
    FLayoutWidth: integer;
    FOnButtonClick: TAIChatButtonEvent;
    FPopup: TPopupMenu;
    FPopupItem: TAIChatItem;
    FUpdating: integer;
    function GetCount: integer;
    function GetItem(AIndex: integer): TAIChatItem;
    function BubbleWidth: integer;
    function TextHeight(const AText: string; AFont: TFont; AWidth: integer): integer;
    procedure MeasureItem(AItem: TAIChatItem);
    procedure Relayout(AFromIndex: integer);
    function AtBottom: boolean;
    procedure ScrollToBottom;
    function ItemAt(Y: integer): TAIChatItem;
    procedure BoxPaint(Sender: TObject);
    procedure BoxResize(Sender: TObject);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure PaintItem(ACanvas: TCanvas; AItem: TAIChatItem);
    procedure PopupCopyMessage(Sender: TObject);
    procedure PopupCopyCode(Sender: TObject);
    procedure PopupCopyAll(Sender: TObject);
    procedure PopupPopup(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Add(AKind: TAIChatItemKind; const AText: string = ''): TAIChatItem;
    procedure AppendText(AItem: TAIChatItem; const AText: string);
    { Call after changing an item's fields directly. }
    procedure Changed(AItem: TAIChatItem);
    function FindItem(AKind: TAIChatItemKind; const AKey: string): TAIChatItem;
    function LastItem: TAIChatItem;
    procedure Clear;
    procedure BeginUpdate;
    procedure EndUpdate;
    function AsText: string;
    property Count: integer read GetCount;
    property Items[AIndex: integer]: TAIChatItem read GetItem;
    property OnButtonClick: TAIChatButtonEvent read FOnButtonClick write FOnButtonClick;
  end;

implementation

const
  MARGIN = 8;
  PAD = 8;
  GAP = 6;
  BUTTON_HEIGHT = 24;
  BUTTON_PAD = 12;
  MAX_COLLAPSED_PREVIEW = 80;
  DRAW_FLAGS = DT_WORDBREAK or DT_NOPREFIX or DT_EXPANDTABS or DT_EDITCONTROL;

function Blend(AColor1, AColor2: TColor; APercent: integer): TColor;
var
  c1, c2: TColor;
begin
  c1 := ColorToRGB(AColor1);
  c2 := ColorToRGB(AColor2);
  Result := RGBToColor(
    (Red(c1) * (100 - APercent) + Red(c2) * APercent) div 100,
    (Green(c1) * (100 - APercent) + Green(c2) * APercent) div 100,
    (Blue(c1) * (100 - APercent) + Blue(c2) * APercent) div 100);
end;

{ TAIChatItem }

function TAIChatItem.Collapsible: boolean;
begin
  Result := Kind in [cikThinking, cikTool, cikPlan];
end;

function TAIChatItem.HeaderText: string;
const
  STATUS_MARK: array[TAIToolStatus] of string = ('…', '▶', '✓', '✗');
var
  fold: string;
begin
  fold := '';
  if Collapsible then
    if Collapsed then
      fold := '▸ '
    else
      fold := '▾ ';
  case Kind of
    cikThinking: Result := fold + 'Thinking';
    cikTool:
    begin
      Result := fold + STATUS_MARK[Status] + ' ' + Title;
      if (Path <> '') and (Pos(ExtractFileName(Path), Title) = 0) then
        Result := Result + '  ' + ExtractFileName(Path);
    end;
    cikPlan: Result := fold + 'Plan';
    cikPermission: Result := 'Permission: ' + Title;
    cikError: Result := 'Error';
    else
      Result := '';
  end;
end;

{ TAIChatView }

constructor TAIChatView.Create(AOwner: TComponent);
var
  mi: TMenuItem;
begin
  inherited Create(AOwner);
  FItems := TObjectList.Create(True);
  BorderStyle := bsNone;
  HorzScrollBar.Visible := False;
  VertScrollBar.Tracking := True;
  VertScrollBar.Increment := 24;
  Color := clWindow;

  FMeasure := TBitmap.Create;
  FMeasure.SetSize(4, 4);
  FCodeFont := TFont.Create;
  FCodeFont.Name := {$IFDEF WINDOWS}'Consolas'{$ELSE}{$IFDEF DARWIN}'Menlo'{$ELSE}'Monospace'{$ENDIF}{$ENDIF};
  FCodeFont.Size := 9;

  FBox := TPaintBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alTop;
  FBox.Height := 10;
  FBox.OnPaint := @BoxPaint;
  FBox.OnResize := @BoxResize;
  FBox.OnMouseUp := @BoxMouseUp;
  FBox.OnMouseMove := @BoxMouseMove;

  FPopup := TPopupMenu.Create(Self);
  FPopup.OnPopup := @PopupPopup;
  mi := TMenuItem.Create(FPopup);
  mi.Caption := 'Copy message';
  mi.OnClick := @PopupCopyMessage;
  FPopup.Items.Add(mi);
  mi := TMenuItem.Create(FPopup);
  mi.Caption := 'Copy code blocks';
  mi.OnClick := @PopupCopyCode;
  FPopup.Items.Add(mi);
  mi := TMenuItem.Create(FPopup);
  mi.Caption := 'Copy conversation';
  mi.OnClick := @PopupCopyAll;
  FPopup.Items.Add(mi);
  FBox.PopupMenu := FPopup;
end;

destructor TAIChatView.Destroy;
begin
  FItems.Free;
  FCodeFont.Free;
  FMeasure.Free;
  inherited Destroy;
end;

function TAIChatView.GetCount: integer;
begin
  Result := FItems.Count;
end;

function TAIChatView.GetItem(AIndex: integer): TAIChatItem;
begin
  Result := TAIChatItem(FItems[AIndex]);
end;

function TAIChatView.LastItem: TAIChatItem;
begin
  if FItems.Count = 0 then
    Result := nil
  else
    Result := TAIChatItem(FItems.Last);
end;

function TAIChatView.BubbleWidth: integer;
begin
  Result := FBox.Width - 2 * MARGIN;
  if Result < 60 then
    Result := 60;
end;

function TAIChatView.TextHeight(const AText: string; AFont: TFont; AWidth: integer): integer;
var
  r: TRect;
begin
  if AText = '' then
    Exit(0);
  FMeasure.Canvas.Font.Assign(AFont);
  r := Rect(0, 0, AWidth, 0);
  DrawText(FMeasure.Canvas.Handle, PChar(AText), Length(AText), r, DRAW_FLAGS or DT_CALCRECT);
  Result := r.Bottom - r.Top;
end;

procedure TAIChatView.MeasureItem(AItem: TAIChatItem);
var
  inner, i, h: integer;
  parts: TStringList;
  boldFont: TFont;
begin
  inner := BubbleWidth - 2 * PAD;
  boldFont := TFont.Create;
  try
    boldFont.Assign(Font);
    boldFont.Style := [fsBold];
    AItem.HeaderHeight := 0;
    if AItem.HeaderText <> '' then
      AItem.HeaderHeight := TextHeight(AItem.HeaderText, boldFont, inner);
  finally
    boldFont.Free;
  end;

  SetLength(AItem.Segments, 0);
  if not (AItem.Collapsible and AItem.Collapsed) then
  begin
    parts := AISplitCodeBlocks(AItem.Text);
    try
      SetLength(AItem.Segments, parts.Count);
      for i := 0 to parts.Count - 1 do
      begin
        AItem.Segments[i].IsCode := parts.Objects[i] <> nil;
        AItem.Segments[i].Text := parts[i];
        if AItem.Segments[i].IsCode then
          AItem.Segments[i].Height := TextHeight(parts[i] + ' ', FCodeFont, inner - 2 * PAD) + 2 * PAD
        else
          AItem.Segments[i].Height := TextHeight(parts[i], Font, inner);
      end;
    finally
      parts.Free;
    end;
  end;

  AItem.ButtonsHeight := 0;
  if (AItem.Kind = cikPermission) and (Length(AItem.Buttons) > 0) then
    AItem.ButtonsHeight := BUTTON_HEIGHT + GAP;

  h := 2 * PAD + AItem.HeaderHeight + AItem.ButtonsHeight;
  for i := 0 to High(AItem.Segments) do
    Inc(h, AItem.Segments[i].Height + GAP);
  if (AItem.HeaderHeight > 0) and (Length(AItem.Segments) = 0) and (AItem.ButtonsHeight = 0) then
    h := AItem.HeaderHeight + 2 * PAD;
  AItem.Height := h;
  AItem.Valid := True;
end;

procedure TAIChatView.Relayout(AFromIndex: integer);
var
  i, y: integer;
  item: TAIChatItem;
  stick: boolean;
begin
  if FUpdating > 0 then
    Exit;
  stick := AtBottom;
  if FLayoutWidth <> FBox.Width then
  begin
    FLayoutWidth := FBox.Width;
    AFromIndex := 0;
    for i := 0 to FItems.Count - 1 do
      Items[i].Valid := False;
  end;
  if AFromIndex < 0 then
    AFromIndex := 0;
  if AFromIndex = 0 then
    y := MARGIN
  else
    y := Items[AFromIndex - 1].Top + Items[AFromIndex - 1].Height + GAP;
  for i := AFromIndex to FItems.Count - 1 do
  begin
    item := Items[i];
    if not item.Valid then
      MeasureItem(item);
    item.Top := y;
    Inc(y, item.Height + GAP);
  end;
  if FBox.Height <> y + MARGIN then
    FBox.Height := y + MARGIN;
  FBox.Invalidate;
  if stick then
    ScrollToBottom;
end;

function TAIChatView.AtBottom: boolean;
begin
  Result := VertScrollBar.Position + ClientHeight >= FBox.Height - 40;
end;

procedure TAIChatView.ScrollToBottom;
begin
  VertScrollBar.Position := FBox.Height;
end;

function TAIChatView.Add(AKind: TAIChatItemKind; const AText: string): TAIChatItem;
begin
  Result := TAIChatItem.Create;
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Collapsed := AKind in [cikThinking, cikTool];
  FItems.Add(Result);
  Relayout(FItems.Count - 1);
  if FUpdating = 0 then
    ScrollToBottom;
end;

procedure TAIChatView.AppendText(AItem: TAIChatItem; const AText: string);
begin
  AItem.Text := AItem.Text + AText;
  Changed(AItem);
end;

procedure TAIChatView.Changed(AItem: TAIChatItem);
begin
  AItem.Valid := False;
  Relayout(FItems.IndexOf(AItem));
end;

function TAIChatView.FindItem(AKind: TAIChatItemKind; const AKey: string): TAIChatItem;
var
  i: integer;
begin
  for i := FItems.Count - 1 downto 0 do
    if (Items[i].Kind = AKind) and (Items[i].Key = AKey) then
      Exit(Items[i]);
  Result := nil;
end;

procedure TAIChatView.Clear;
begin
  FItems.Clear;
  Relayout(0);
end;

procedure TAIChatView.BeginUpdate;
begin
  Inc(FUpdating);
end;

procedure TAIChatView.EndUpdate;
begin
  Dec(FUpdating);
  if FUpdating = 0 then
    Relayout(0);
end;

function TAIChatView.AsText: string;
const
  PREFIX: array[TAIChatItemKind] of string =
    ('You', 'Assistant', 'Thinking', 'Tool', 'Plan', 'Permission', 'Error', 'Info');
var
  i: integer;
  item: TAIChatItem;
begin
  Result := '';
  for i := 0 to FItems.Count - 1 do
  begin
    item := Items[i];
    Result := Result + '[' + PREFIX[item.Kind];
    if item.Title <> '' then
      Result := Result + ': ' + item.Title;
    Result := Result + ']' + LineEnding + item.Text + LineEnding + LineEnding;
  end;
end;

function TAIChatView.ItemAt(Y: integer): TAIChatItem;
var
  i: integer;
begin
  for i := 0 to FItems.Count - 1 do
    if (Y >= Items[i].Top) and (Y < Items[i].Top + Items[i].Height) then
      Exit(Items[i]);
  Result := nil;
end;

procedure TAIChatView.BoxResize(Sender: TObject);
begin
  if FBox.Width <> FLayoutWidth then
    Relayout(0);
end;

procedure TAIChatView.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  item: TAIChatItem;
  i: integer;
  hand: boolean;
begin
  hand := False;
  item := ItemAt(Y);
  if Assigned(item) then
  begin
    if item.Collapsible and (Y < item.Top + PAD + item.HeaderHeight) then
      hand := True;
    if item.Answer = '' then
      for i := 0 to High(item.Buttons) do
        if PtInRect(item.Buttons[i].Rect, Point(X, Y)) then
          hand := True;
  end;
  if hand then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
end;

procedure TAIChatView.BoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  item: TAIChatItem;
  i: integer;
begin
  if Button <> mbLeft then
    Exit;
  item := ItemAt(Y);
  if not Assigned(item) then
    Exit;
  if (item.Kind = cikPermission) and (item.Answer = '') then
    for i := 0 to High(item.Buttons) do
      if PtInRect(item.Buttons[i].Rect, Point(X, Y)) then
      begin
        if Assigned(FOnButtonClick) then
          FOnButtonClick(Self, item, item.Buttons[i].Id);
        Exit;
      end;
  if item.Collapsible and (Y < item.Top + PAD + item.HeaderHeight) then
  begin
    item.Collapsed := not item.Collapsed;
    Changed(item);
  end;
end;

procedure TAIChatView.BoxPaint(Sender: TObject);
var
  i: integer;
  clip: TRect;
  item: TAIChatItem;
begin
  clip := FBox.Canvas.ClipRect;
  FBox.Canvas.Brush.Color := Color;
  FBox.Canvas.FillRect(clip);
  for i := 0 to FItems.Count - 1 do
  begin
    item := Items[i];
    if item.Top > clip.Bottom then
      Break;
    if item.Top + item.Height < clip.Top then
      Continue;
    PaintItem(FBox.Canvas, item);
  end;
end;

procedure TAIChatView.PaintItem(ACanvas: TCanvas; AItem: TAIChatItem);
var
  bubble, r: TRect;
  back, fore, accent: TColor;
  i, y, x, inner, w: integer;
  s: string;
begin
  fore := clWindowText;
  accent := clHighlight;
  case AItem.Kind of
    cikUser: back := Blend(clWindow, clHighlight, 18);
    cikAssistant: back := clWindow;
    cikError:
    begin
      back := Blend(clWindow, clRed, 15);
      accent := clRed;
    end;
    cikPermission:
    begin
      back := Blend(clWindow, $0080FF, 15);
      accent := $0060C0;
    end;
    cikInfo:
    begin
      back := clWindow;
      fore := clGrayText;
    end;
    else
    begin
      back := Blend(clWindow, clWindowText, 6);
      fore := Blend(clWindowText, clWindow, 25);
    end;
  end;

  bubble := Rect(MARGIN, AItem.Top, MARGIN + BubbleWidth, AItem.Top + AItem.Height);
  ACanvas.Brush.Color := back;
  if AItem.Kind in [cikAssistant, cikInfo] then
    ACanvas.Pen.Color := back
  else
    ACanvas.Pen.Color := Blend(back, clWindowText, 12);
  ACanvas.RoundRect(bubble, 8, 8);

  inner := BubbleWidth - 2 * PAD;
  y := bubble.Top + PAD;
  x := bubble.Left + PAD;
  ACanvas.Brush.Style := bsClear;

  if AItem.HeaderHeight > 0 then
  begin
    ACanvas.Font.Assign(Font);
    ACanvas.Font.Style := [fsBold];
    if AItem.Kind = cikTool then
      case AItem.Status of
        atsCompleted: ACanvas.Font.Color := Blend(clWindowText, clGreen, 60);
        atsFailed: ACanvas.Font.Color := clRed;
        else
          ACanvas.Font.Color := fore;
      end
    else if AItem.Kind in [cikError, cikPermission] then
      ACanvas.Font.Color := accent
    else
      ACanvas.Font.Color := fore;
    s := AItem.HeaderText;
    r := Rect(x, y, x + inner, y + AItem.HeaderHeight);
    DrawText(ACanvas.Handle, PChar(s), Length(s), r, DRAW_FLAGS);
    Inc(y, AItem.HeaderHeight);
    if Length(AItem.Segments) > 0 then
      Inc(y, GAP);
  end;

  for i := 0 to High(AItem.Segments) do
  begin
    s := AItem.Segments[i].Text;
    if AItem.Segments[i].IsCode then
    begin
      r := Rect(x, y, x + inner, y + AItem.Segments[i].Height);
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := Blend(back, clWindowText, 8);
      ACanvas.Pen.Color := ACanvas.Brush.Color;
      ACanvas.RoundRect(r, 6, 6);
      ACanvas.Brush.Style := bsClear;
      ACanvas.Font.Assign(FCodeFont);
      ACanvas.Font.Color := fore;
      InflateRect(r, -PAD, -PAD);
      s := s + ' ';
    end
    else
    begin
      ACanvas.Font.Assign(Font);
      ACanvas.Font.Color := fore;
      r := Rect(x, y, x + inner, y + AItem.Segments[i].Height);
    end;
    DrawText(ACanvas.Handle, PChar(s), Length(s), r, DRAW_FLAGS);
    Inc(y, AItem.Segments[i].Height + GAP);
  end;

  if AItem.ButtonsHeight > 0 then
  begin
    ACanvas.Font.Assign(Font);
    if AItem.Answer <> '' then
    begin
      ACanvas.Font.Color := clGrayText;
      ACanvas.TextOut(x, y + 4, 'Answered: ' + AItem.Answer);
      for i := 0 to High(AItem.Buttons) do
        AItem.Buttons[i].Rect := Rect(0, 0, 0, 0);
    end
    else
      for i := 0 to High(AItem.Buttons) do
      begin
        w := ACanvas.TextWidth(AItem.Buttons[i].Caption) + 2 * BUTTON_PAD;
        r := Rect(x, y, x + w, y + BUTTON_HEIGHT);
        AItem.Buttons[i].Rect := r;
        ACanvas.Brush.Style := bsSolid;
        if Pos('allow', AItem.Buttons[i].Kind) = 1 then
        begin
          ACanvas.Brush.Color := clHighlight;
          ACanvas.Font.Color := clHighlightText;
        end
        else
        begin
          ACanvas.Brush.Color := clBtnFace;
          ACanvas.Font.Color := clBtnText;
        end;
        ACanvas.Pen.Color := Blend(ACanvas.Brush.Color, clWindowText, 25);
        ACanvas.RoundRect(r, 6, 6);
        ACanvas.Brush.Style := bsClear;
        ACanvas.TextOut(r.Left + BUTTON_PAD,
          r.Top + (BUTTON_HEIGHT - ACanvas.TextHeight('Ag')) div 2, AItem.Buttons[i].Caption);
        x := r.Right + GAP;
      end;
  end;
  ACanvas.Brush.Style := bsSolid;
end;

procedure TAIChatView.PopupPopup(Sender: TObject);
var
  p: TPoint;
begin
  p := FBox.ScreenToClient(Mouse.CursorPos);
  FPopupItem := ItemAt(p.Y);
  FPopup.Items[0].Enabled := Assigned(FPopupItem);
  FPopup.Items[1].Enabled := Assigned(FPopupItem) and (Pos('```', FPopupItem.Text) > 0);
end;

procedure TAIChatView.PopupCopyMessage(Sender: TObject);
begin
  if Assigned(FPopupItem) then
    Clipboard.AsText := FPopupItem.Text;
end;

procedure TAIChatView.PopupCopyCode(Sender: TObject);
var
  parts: TStringList;
  i: integer;
  s: string;
begin
  if not Assigned(FPopupItem) then
    Exit;
  s := '';
  parts := AISplitCodeBlocks(FPopupItem.Text);
  try
    for i := 0 to parts.Count - 1 do
      if parts.Objects[i] <> nil then
        s := s + parts[i] + LineEnding;
  finally
    parts.Free;
  end;
  Clipboard.AsText := s;
end;

procedure TAIChatView.PopupCopyAll(Sender: TObject);
begin
  Clipboard.AsText := AsText;
end;

end.
