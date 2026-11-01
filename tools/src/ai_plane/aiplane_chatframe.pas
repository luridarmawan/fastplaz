unit aiplane_chatframe;

{
  The AI Plane chat as a frame, so the IDE window and the tester app show the
  same thing:

    [Runtime v] [Model v] [Effort v]           [New] [Log]
    +----------------------------------------------------+
    | conversation (TAIChatView)                          |
    +----------------------------------------------------+
    | log (hidden by default)                             |
    +----------------------------------------------------+
    | input                                     [Send]   |
    status: agent - model - session - usage

  Enter sends, Shift+Enter adds a line, Esc stops the running turn. The
  adapter is polled from a timer, so all events arrive in the main thread.

  The host sets the runtime (SetRuntime), the working directory and,
  optionally, OnReadFile to serve unsaved editor buffers. OnSettingsChanged
  tells it to persist runtime/model/effort.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Buttons, LCLType,
  aiplane_types, aiplane_presets, aiplane_chatview;

type

  { TAIChatFrame }

  TAIChatFrame = class(TFrame)
  private
    FAdapter: TAIAdapter;
    FTop: TPanel;
    FRuntimeBox: TComboBox;
    FModelBox: TComboBox;
    FEffortBox: TComboBox;
    FNewButton: TButton;
    FLogButton: TSpeedButton;
    FView: TAIChatView;
    FLog: TMemo;
    FLogSplitter: TSplitter;
    FBottom: TPanel;
    FInput: TMemo;
    FSendButton: TButton;
    FStatus: TLabel;
    FTimer: TTimer;
    FPresetId: string;
    FCommand: string;
    FArguments: string;
    FWorkingDir: string;
    FAgentText, FModelText, FSessionText, FUsageText: string;
    FCurrentText: TAIChatItem;
    FCurrentThinking: TAIChatItem;
    FOnReadFile: TAIReadFileHandler;
    FOnSettingsChanged: TNotifyEvent;
    FFillingModels: boolean;
    FModelCount: integer;
    procedure BuildControls;
    procedure CreateAdapter;
    procedure FreeAdapter;
    procedure UpdateControls;
    procedure UpdateStatus;
    procedure FillModels;
    procedure Send;
    procedure AdapterEvent(Sender: TObject; const AEvent: TAIEvent);
    procedure AdapterPermission(Sender: TObject; const ARequest: TAIPermissionRequest);
    function AdapterReadFile(Sender: TObject; const APath: string; out AContent: string): boolean;
    procedure ViewButtonClick(Sender: TObject; AItem: TAIChatItem; const AButtonId: string);
    procedure TimerTick(Sender: TObject);
    procedure RuntimeSelect(Sender: TObject);
    procedure ModelChange(Sender: TObject);
    procedure EffortSelect(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure LogClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure InputKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    function GetEffort: string;
    function GetModel: string;
    procedure SetEffort(const AValue: string);
    procedure SetModel(const AValue: string);
    procedure SetWorkingDir(const AValue: string);
    procedure DoSettingsChanged;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Switches runtime. ACommand/AArguments override the preset when not
      empty. Stops the current runtime. }
    procedure SetRuntime(const APresetId: string; const ACommand: string = '';
      const AArguments: string = '');
    procedure SendPrompt(const AText: string);
    procedure NewChat;
    procedure FocusInput;
    property Adapter: TAIAdapter read FAdapter;
    property View: TAIChatView read FView;
    property PresetId: string read FPresetId;
    property Command: string read FCommand;
    property Arguments: string read FArguments;
    property Model: string read GetModel write SetModel;
    property Effort: string read GetEffort write SetEffort;
    property WorkingDir: string read FWorkingDir write SetWorkingDir;
    property OnReadFile: TAIReadFileHandler read FOnReadFile write FOnReadFile;
    property OnSettingsChanged: TNotifyEvent read FOnSettingsChanged write FOnSettingsChanged;
  end;

implementation

{$R *.lfm}

const
  MAX_LOG_LINES = 2000;

{ TAIChatFrame }

constructor TAIChatFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildControls;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 30;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
  if AIPresetCount > 0 then
    SetRuntime(AIPreset(0).Id);
end;

destructor TAIChatFrame.Destroy;
begin
  FTimer.Enabled := False;
  FreeAdapter;
  inherited Destroy;
end;

procedure TAIChatFrame.BuildControls;
var
  i: integer;
begin
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.AutoSize := True;
  FTop.ChildSizing.LeftRightSpacing := 4;
  FTop.ChildSizing.TopBottomSpacing := 4;
  FTop.ChildSizing.HorizontalSpacing := 4;

  FRuntimeBox := TComboBox.Create(Self);
  FRuntimeBox.Parent := FTop;
  FRuntimeBox.Style := csDropDownList;
  FRuntimeBox.Width := 130;
  FRuntimeBox.Hint := 'Runtime';
  for i := 0 to AIPresetCount - 1 do
    FRuntimeBox.Items.Add(AIPreset(i).Title);
  FRuntimeBox.OnSelect := @RuntimeSelect;

  FModelBox := TComboBox.Create(Self);
  FModelBox.Parent := FTop;
  FModelBox.Width := 170;
  FModelBox.Hint := 'Model (empty = runtime default)';
  FModelBox.OnSelect := @ModelChange;
  FModelBox.OnEditingDone := @ModelChange;

  FEffortBox := TComboBox.Create(Self);
  FEffortBox.Parent := FTop;
  FEffortBox.Style := csDropDownList;
  FEffortBox.Width := 80;
  FEffortBox.Hint := 'Thinking effort';
  for i := 0 to High(AI_EFFORT_LEVELS) do
    FEffortBox.Items.Add(AI_EFFORT_LEVELS[i]);
  FEffortBox.ItemIndex := 0;
  FEffortBox.OnSelect := @EffortSelect;

  FNewButton := TButton.Create(Self);
  FNewButton.Parent := FTop;
  FNewButton.Caption := 'New';
  FNewButton.Hint := 'New conversation';
  FNewButton.AutoSize := True;
  FNewButton.OnClick := @NewClick;

  FLogButton := TSpeedButton.Create(Self);
  FLogButton.Parent := FTop;
  FLogButton.Caption := 'Log';
  FLogButton.Hint := 'Show protocol log';
  FLogButton.AllowAllUp := True;
  FLogButton.GroupIndex := 1;
  FLogButton.Width := 40;
  FLogButton.OnClick := @LogClick;

  FTop.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  FTop.ChildSizing.ControlsPerLine := 5;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.BorderSpacing.Around := 4;
  FStatus.Font.Color := clGrayText;
  FStatus.ShowAccelChar := False;
  FStatus.Caption := '';

  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.BevelOuter := bvNone;
  FBottom.Height := 72;

  FSendButton := TButton.Create(Self);
  FSendButton.Parent := FBottom;
  FSendButton.Align := alRight;
  FSendButton.BorderSpacing.Around := 4;
  FSendButton.Width := 64;
  FSendButton.Caption := 'Send';
  FSendButton.OnClick := @SendClick;

  FInput := TMemo.Create(Self);
  FInput.Parent := FBottom;
  FInput.Align := alClient;
  FInput.BorderSpacing.Around := 4;
  FInput.ScrollBars := ssAutoVertical;
  FInput.WantReturns := True;
  FInput.WordWrap := True;
  FInput.OnKeyDown := @InputKeyDown;
  FInput.TextHint := 'Ask the agent (Enter to send, Shift+Enter for a new line)';

  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.Align := alBottom;
  FLog.Height := 120;
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssAutoBoth;
  FLog.WordWrap := False;
  FLog.Visible := False;

  FLogSplitter := TSplitter.Create(Self);
  FLogSplitter.Parent := Self;
  FLogSplitter.Align := alBottom;
  FLogSplitter.Visible := False;

  FView := TAIChatView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnButtonClick := @ViewButtonClick;

  ShowHint := True;
end;

procedure TAIChatFrame.SetRuntime(const APresetId: string; const ACommand: string;
  const AArguments: string);
var
  i: integer;
  keep: string;
begin
  FPresetId := APresetId;
  FCommand := ACommand;
  FArguments := AArguments;
  for i := 0 to AIPresetCount - 1 do
    if SameText(AIPreset(i).Id, APresetId) then
      FRuntimeBox.ItemIndex := i;
  keep := GetModel;
  FreeAdapter;
  FModelBox.Items.Clear;
  FModelBox.Text := keep;
  FModelCount := -1;
  CreateAdapter;
end;

procedure TAIChatFrame.CreateAdapter;
var
  keepModel, keepEffort: string;
begin
  keepModel := GetModel;
  keepEffort := GetEffort;
  try
    FAdapter := AICreateAdapter(FPresetId, FCommand, FArguments);
  except
    on E: Exception do
    begin
      FAdapter := nil;
      FView.Add(cikError, E.Message);
      UpdateControls;
      Exit;
    end;
  end;
  FAdapter.OnEvent := @AdapterEvent;
  FAdapter.OnPermission := @AdapterPermission;
  FAdapter.OnReadFile := @AdapterReadFile;
  FAdapter.WorkingDir := FWorkingDir;
  FAdapter.Model := keepModel;
  FAdapter.Effort := keepEffort;
  FAgentText := FAdapter.Command;
  FModelText := '';
  FSessionText := '';
  FUsageText := '';
  FillModels;
  UpdateControls;
  UpdateStatus;
end;

procedure TAIChatFrame.FreeAdapter;
begin
  if not Assigned(FAdapter) then
    Exit;
  FTimer.Enabled := False;
  FAdapter.OnEvent := nil;
  FAdapter.OnPermission := nil;
  try
    FAdapter.Stop;
  except
  end;
  FreeAndNil(FAdapter);
  FCurrentText := nil;
  FCurrentThinking := nil;
end;

procedure TAIChatFrame.UpdateControls;
var
  busy: boolean;
begin
  busy := Assigned(FAdapter) and FAdapter.IsBusy;
  if busy then
    FSendButton.Caption := 'Stop'
  else
    FSendButton.Caption := 'Send';
  FSendButton.Enabled := Assigned(FAdapter);
  FRuntimeBox.Enabled := not busy;
  FNewButton.Enabled := not busy;
end;

procedure TAIChatFrame.UpdateStatus;
var
  s: string;

  procedure AddPart(const APart: string);
  begin
    if APart = '' then
      Exit;
    if s <> '' then
      s := s + '  ·  ';
    s := s + APart;
  end;

begin
  s := '';
  AddPart(FAgentText);
  AddPart(FModelText);
  if Assigned(FAdapter) then
    AddPart(AIStateToString(FAdapter.State));
  AddPart(FUsageText);
  FStatus.Caption := s;
  FStatus.Hint := FSessionText;
end;

procedure TAIChatFrame.FillModels;
var
  i: integer;
  keep: string;
begin
  if not Assigned(FAdapter) or (Length(FAdapter.Models) = FModelCount) then
    Exit;
  FModelCount := Length(FAdapter.Models);
  FFillingModels := True;
  try
    keep := FModelBox.Text;
    FModelBox.Items.BeginUpdate;
    try
      FModelBox.Items.Clear;
      for i := 0 to High(FAdapter.Models) do
        FModelBox.Items.Add(FAdapter.Models[i].Id);
    finally
      FModelBox.Items.EndUpdate;
    end;
    // Show what the runtime uses until the user picks something else.
    if keep = '' then
      keep := FModelText;
    FModelBox.Text := keep;
  finally
    FFillingModels := False;
  end;
end;

procedure TAIChatFrame.SendPrompt(const AText: string);
begin
  if Trim(AText) = '' then
    Exit;
  if not Assigned(FAdapter) then
    CreateAdapter;
  if not Assigned(FAdapter) or FAdapter.IsBusy then
    Exit;
  FView.Add(cikUser, AText);
  FCurrentText := nil;
  FCurrentThinking := nil;
  FTimer.Enabled := True;
  try
    FAdapter.Prompt(AText);
  except
    on E: Exception do
      FView.Add(cikError, E.Message);
  end;
  UpdateControls;
  UpdateStatus;
end;

procedure TAIChatFrame.Send;
var
  s: string;
begin
  if Assigned(FAdapter) and FAdapter.IsBusy then
  begin
    FAdapter.Cancel;
    Exit;
  end;
  s := FInput.Text;
  if Trim(s) = '' then
    Exit;
  FInput.Clear;
  SendPrompt(s);
end;

procedure TAIChatFrame.NewChat;
begin
  if Assigned(FAdapter) and FAdapter.IsBusy then
    Exit;
  FView.Clear;
  FCurrentText := nil;
  FCurrentThinking := nil;
  FUsageText := '';
  if Assigned(FAdapter) then
  begin
    try
      FAdapter.NewSession;
    except
      on E: Exception do
        FView.Add(cikError, E.Message);
    end;
    FTimer.Enabled := True;
  end;
  UpdateStatus;
end;

procedure TAIChatFrame.FocusInput;
begin
  if FInput.CanFocus then
    FInput.SetFocus;
end;

procedure TAIChatFrame.AdapterEvent(Sender: TObject; const AEvent: TAIEvent);
var
  item: TAIChatItem;
begin
  case AEvent.Kind of
    aekText:
    begin
      if not Assigned(FCurrentText) or (FView.LastItem <> FCurrentText) then
        FCurrentText := FView.Add(cikAssistant);
      FView.AppendText(FCurrentText, AEvent.Text);
    end;
    aekThinking:
    begin
      if not Assigned(FCurrentThinking) or (FView.LastItem <> FCurrentThinking) then
        FCurrentThinking := FView.Add(cikThinking);
      FView.AppendText(FCurrentThinking, AEvent.Text);
    end;
    aekToolCall, aekToolUpdate:
    begin
      item := nil;
      if AEvent.ToolCallId <> '' then
        item := FView.FindItem(cikTool, AEvent.ToolCallId);
      if not Assigned(item) then
      begin
        item := FView.Add(cikTool);
        item.Key := AEvent.ToolCallId;
        item.Title := 'tool';
      end;
      if AEvent.ToolTitle <> '' then
        item.Title := AEvent.ToolTitle;
      if AEvent.ToolPath <> '' then
        item.Path := AEvent.ToolPath;
      item.Status := AEvent.ToolStatus;
      if AEvent.Text <> '' then
        item.Text := AEvent.Text;
      FView.Changed(item);
    end;
    aekPlan:
    begin
      item := FView.FindItem(cikPlan, 'plan');
      if not Assigned(item) or (FView.LastItem <> item) then
      begin
        item := FView.Add(cikPlan);
        item.Key := 'plan';
      end;
      item.Text := Trim(AEvent.Text);
      FView.Changed(item);
    end;
    aekError:
      FView.Add(cikError, AEvent.Text);
    aekDone:
    begin
      if (AEvent.StopReason <> '') and (AEvent.StopReason <> 'end_turn') and
        (AEvent.StopReason <> 'error') then
        FView.Add(cikInfo, 'Stopped: ' + AEvent.StopReason);
      FCurrentText := nil;
      FCurrentThinking := nil;
      FillModels;
    end;
    aekStatus:
    begin
      if Copy(AEvent.Text, 1, 7) = 'agent: ' then
        FAgentText := Copy(AEvent.Text, 8, MaxInt)
      else if Copy(AEvent.Text, 1, 7) = 'model: ' then
      begin
        FModelText := Copy(AEvent.Text, 8, MaxInt);
        FillModels;
      end
      else if Copy(AEvent.Text, 1, 9) = 'session: ' then
        FSessionText := AEvent.Text;
      UpdateStatus;
      UpdateControls;
    end;
    aekUsage:
    begin
      FUsageText := AEvent.Text;
      UpdateStatus;
    end;
    aekLog:
      if FLog.Visible then
      begin
        if FLog.Lines.Count > MAX_LOG_LINES then
          FLog.Lines.Clear;
        FLog.Lines.Add(Copy(AEvent.Text, 1, 2000));
      end;
  end;
  if AEvent.Kind = aekDone then
    UpdateControls;
end;

procedure TAIChatFrame.AdapterPermission(Sender: TObject;
  const ARequest: TAIPermissionRequest);
var
  item: TAIChatItem;
  i: integer;
begin
  item := FView.Add(cikPermission, ARequest.Detail);
  item.Key := ARequest.Key;
  item.Title := ARequest.ToolTitle;
  SetLength(item.Buttons, Length(ARequest.Options));
  for i := 0 to High(ARequest.Options) do
  begin
    item.Buttons[i].Id := ARequest.Options[i].Id;
    item.Buttons[i].Caption := ARequest.Options[i].Name;
    item.Buttons[i].Kind := ARequest.Options[i].Kind;
  end;
  FView.Changed(item);
  // A new item while the text streams starts a new text item after it.
  FCurrentText := nil;
end;

function TAIChatFrame.AdapterReadFile(Sender: TObject; const APath: string;
  out AContent: string): boolean;
begin
  Result := Assigned(FOnReadFile) and FOnReadFile(Self, APath, AContent);
end;

procedure TAIChatFrame.ViewButtonClick(Sender: TObject; AItem: TAIChatItem;
  const AButtonId: string);
var
  i: integer;
begin
  if not Assigned(FAdapter) or (AItem.Answer <> '') then
    Exit;
  for i := 0 to High(AItem.Buttons) do
    if AItem.Buttons[i].Id = AButtonId then
      AItem.Answer := AItem.Buttons[i].Caption;
  FView.Changed(AItem);
  FAdapter.RespondPermission(AItem.Key, AButtonId);
end;

procedure TAIChatFrame.TimerTick(Sender: TObject);
var
  rounds: integer;
begin
  if not Assigned(FAdapter) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  // Drain a burst of output, but give the UI back regularly.
  rounds := 0;
  while FAdapter.Poll and (rounds < 20) do
    Inc(rounds);
  if FAdapter.State in [aasIdle, aasStopped, aasFailed] then
  begin
    FTimer.Enabled := False;
    UpdateControls;
    UpdateStatus;
  end;
end;

procedure TAIChatFrame.RuntimeSelect(Sender: TObject);
begin
  if (FRuntimeBox.ItemIndex < 0) or
    SameText(AIPreset(FRuntimeBox.ItemIndex).Id, FPresetId) then
    Exit;
  FModelBox.Text := '';
  SetRuntime(AIPreset(FRuntimeBox.ItemIndex).Id);
  FView.Add(cikInfo, 'Runtime: ' + AIPreset(FRuntimeBox.ItemIndex).Title);
  DoSettingsChanged;
end;

procedure TAIChatFrame.ModelChange(Sender: TObject);
begin
  if FFillingModels or not Assigned(FAdapter) then
    Exit;
  if FAdapter.Model = Trim(FModelBox.Text) then
    Exit;
  // The runtime's own model is only shown, not chosen.
  if (FAdapter.Model = '') and (Trim(FModelBox.Text) = FModelText) then
    Exit;
  FAdapter.Model := Trim(FModelBox.Text);
  DoSettingsChanged;
end;

procedure TAIChatFrame.EffortSelect(Sender: TObject);
begin
  if Assigned(FAdapter) then
    FAdapter.Effort := GetEffort;
  DoSettingsChanged;
end;

procedure TAIChatFrame.NewClick(Sender: TObject);
begin
  NewChat;
  FocusInput;
end;

procedure TAIChatFrame.LogClick(Sender: TObject);
begin
  FLog.Visible := FLogButton.Down;
  FLogSplitter.Visible := FLog.Visible;
  if FLog.Visible then
    FLogSplitter.Top := FLog.Top - FLogSplitter.Height;
end;

procedure TAIChatFrame.SendClick(Sender: TObject);
begin
  Send;
  FocusInput;
end;

procedure TAIChatFrame.InputKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and not (ssShift in Shift) and not (ssCtrl in Shift) then
  begin
    Key := 0;
    if not (Assigned(FAdapter) and FAdapter.IsBusy) then
      Send;
  end
  else if (Key = VK_ESCAPE) and Assigned(FAdapter) and FAdapter.IsBusy then
  begin
    Key := 0;
    FAdapter.Cancel;
  end;
end;

function TAIChatFrame.GetEffort: string;
begin
  if FEffortBox.ItemIndex < 0 then
    Result := 'auto'
  else
    Result := FEffortBox.Items[FEffortBox.ItemIndex];
end;

function TAIChatFrame.GetModel: string;
begin
  // The model the user chose; the box may only show the runtime default.
  if Assigned(FAdapter) then
    Result := FAdapter.Model
  else
    Result := Trim(FModelBox.Text);
end;

procedure TAIChatFrame.SetEffort(const AValue: string);
var
  i: integer;
begin
  i := FEffortBox.Items.IndexOf(LowerCase(AValue));
  if i < 0 then
    i := 0;
  FEffortBox.ItemIndex := i;
  if Assigned(FAdapter) then
    FAdapter.Effort := GetEffort;
end;

procedure TAIChatFrame.SetModel(const AValue: string);
begin
  FModelBox.Text := AValue;
  if Assigned(FAdapter) then
    FAdapter.Model := Trim(AValue);
end;

procedure TAIChatFrame.SetWorkingDir(const AValue: string);
begin
  FWorkingDir := AValue;
  if Assigned(FAdapter) then
    FAdapter.WorkingDir := AValue;
end;

procedure TAIChatFrame.DoSettingsChanged;
begin
  if Assigned(FOnSettingsChanged) then
    FOnSettingsChanged(Self);
end;

end.
