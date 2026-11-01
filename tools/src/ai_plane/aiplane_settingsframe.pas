unit aiplane_settingsframe;

{
  AI Plane default settings: runtime, command, arguments, model and effort,
  with model detection and a "Run Test" that sends one prompt.

  Used by the AI Plane tab of Fast Code Configuration and by the tester app;
  the host loads and stores the values (Runtime, Command, ... properties).

  Detection starts the runtime and waits for its session (ACP agents report
  their models there); Claude Code has a fixed list of aliases. Everything is
  polled from a timer, no threads.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  aiplane_types, aiplane_presets;

type

  { TAIPlaneSettingsFrame }

  TAIPlaneSettingsFrame = class(TFrame)
  private
    FRuntimeBox: TComboBox;
    FCommandEdit: TEdit;
    FArgsEdit: TEdit;
    FModelBox: TComboBox;
    FDetectButton: TButton;
    FEffortBox: TComboBox;
    FNoteLabel: TLabel;
    FTestButton: TButton;
    FStatusLabel: TLabel;
    FOutput: TMemo;
    FTimer: TTimer;
    FProbe: TAIAdapter;
    FProbeTesting: boolean;
    FProbeStarted: QWord;
    FProbeText: string;
    FProbeError: string;
    FWorkingDir: string;
    FOnChange: TNotifyEvent;
    procedure BuildControls;
    function AddRow(const ACaption: string; AControl: TControl; ATop: integer): integer;
    procedure UpdateNote;
    procedure StartProbe(ATest: boolean);
    procedure FinishProbe(const AMessage: string);
    procedure ProbeEvent(Sender: TObject; const AEvent: TAIEvent);
    procedure ProbePermission(Sender: TObject; const ARequest: TAIPermissionRequest);
    procedure TimerTick(Sender: TObject);
    procedure RuntimeSelect(Sender: TObject);
    procedure DetectClick(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure ValueChange(Sender: TObject);
    function GetRuntime: string;
    procedure SetRuntime(const AValue: string);
    function GetCommand: string;
    procedure SetCommand(const AValue: string);
    function GetArguments: string;
    procedure SetArguments(const AValue: string);
    function GetModel: string;
    procedure SetModel(const AValue: string);
    function GetEffort: string;
    procedure SetEffort(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Fills the model list for the selected runtime. }
    procedure DetectModels;
    { Starts the runtime and sends AIPLANE_TEST_PROMPT. }
    procedure RunTest;
    function Busy: boolean;
    property Runtime: string read GetRuntime write SetRuntime;
    property Command: string read GetCommand write SetCommand;
    property Arguments: string read GetArguments write SetArguments;
    property Model: string read GetModel write SetModel;
    property Effort: string read GetEffort write SetEffort;
    { Where the test runs the runtime ('' = current directory). }
    property WorkingDir: string read FWorkingDir write FWorkingDir;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

const
  AIPLANE_TEST_PROMPT = 'Reply with exactly one word: OK';
  AIPLANE_PROBE_TIMEOUT_MS = 90000;

implementation

{$R *.lfm}

const
  LABEL_WIDTH = 90;
  ROW_HEIGHT = 32;

{ TAIPlaneSettingsFrame }

constructor TAIPlaneSettingsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildControls;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 30;
  FTimer.OnTimer := @TimerTick;
  if AIPresetCount > 0 then
    FRuntimeBox.ItemIndex := 0;
  UpdateNote;
end;

destructor TAIPlaneSettingsFrame.Destroy;
begin
  FTimer.Enabled := False;
  if Assigned(FProbe) then
  begin
    FProbe.OnEvent := nil;
    FProbe.Stop;
    FreeAndNil(FProbe);
  end;
  inherited Destroy;
end;

function TAIPlaneSettingsFrame.AddRow(const ACaption: string; AControl: TControl;
  ATop: integer): integer;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := Self;
  lbl.Caption := ACaption;
  lbl.Left := 8;
  lbl.Top := ATop + 4;
  AControl.Parent := Self;
  AControl.Left := LABEL_WIDTH + 8;
  AControl.Top := ATop;
  AControl.Width := Width - LABEL_WIDTH - 16;
  AControl.Anchors := [akLeft, akTop, akRight];
  Result := ATop + ROW_HEIGHT;
end;

procedure TAIPlaneSettingsFrame.BuildControls;
var
  y, i: integer;
begin
  y := 8;

  FRuntimeBox := TComboBox.Create(Self);
  FRuntimeBox.Style := csDropDownList;
  for i := 0 to AIPresetCount - 1 do
    FRuntimeBox.Items.Add(AIPreset(i).Title);
  FRuntimeBox.OnSelect := @RuntimeSelect;
  y := AddRow('Runtime :', FRuntimeBox, y);

  FCommandEdit := TEdit.Create(Self);
  FCommandEdit.OnChange := @ValueChange;
  y := AddRow('Command :', FCommandEdit, y);

  FArgsEdit := TEdit.Create(Self);
  FArgsEdit.OnChange := @ValueChange;
  y := AddRow('Arguments :', FArgsEdit, y);

  FModelBox := TComboBox.Create(Self);
  FModelBox.TextHint := 'runtime default';
  FModelBox.OnChange := @ValueChange;
  y := AddRow('Model :', FModelBox, y);
  FModelBox.Width := FModelBox.Width - 88;
  FDetectButton := TButton.Create(Self);
  FDetectButton.Parent := Self;
  FDetectButton.Caption := 'Detect';
  FDetectButton.Hint := 'Start the runtime and read its model list';
  FDetectButton.SetBounds(Width - 88, FModelBox.Top, 80, FModelBox.Height);
  FDetectButton.Anchors := [akTop, akRight];
  FDetectButton.OnClick := @DetectClick;

  FEffortBox := TComboBox.Create(Self);
  FEffortBox.Style := csDropDownList;
  for i := 0 to High(AI_EFFORT_LEVELS) do
    FEffortBox.Items.Add(AI_EFFORT_LEVELS[i]);
  FEffortBox.ItemIndex := 0;
  FEffortBox.OnSelect := @ValueChange;
  y := AddRow('Effort :', FEffortBox, y);
  FEffortBox.Width := 120;
  FEffortBox.Anchors := [akLeft, akTop];

  FNoteLabel := TLabel.Create(Self);
  FNoteLabel.Parent := Self;
  FNoteLabel.Left := LABEL_WIDTH + 8;
  FNoteLabel.Top := y;
  FNoteLabel.Font.Color := clGrayText;
  FNoteLabel.ShowAccelChar := False;
  Inc(y, 24);

  FTestButton := TButton.Create(Self);
  FTestButton.Parent := Self;
  FTestButton.Caption := 'Run Test';
  FTestButton.Hint := 'Start the runtime and send: ' + AIPLANE_TEST_PROMPT;
  FTestButton.SetBounds(LABEL_WIDTH + 8, y, 100, 28);
  FTestButton.OnClick := @TestClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Left := LABEL_WIDTH + 116;
  FStatusLabel.Top := y + 6;
  FStatusLabel.ShowAccelChar := False;
  Inc(y, 36);

  FOutput := TMemo.Create(Self);
  FOutput.Parent := Self;
  FOutput.SetBounds(8, y, Width - 16, Height - y - 8);
  FOutput.Anchors := [akLeft, akTop, akRight, akBottom];
  FOutput.ReadOnly := True;
  FOutput.ScrollBars := ssAutoBoth;
  FOutput.WordWrap := False;

  ShowHint := True;
end;

procedure TAIPlaneSettingsFrame.UpdateNote;
var
  preset: TAIRuntimePreset;
begin
  if AIFindPreset(GetRuntime, preset) then
  begin
    FCommandEdit.TextHint := preset.Command;
    FArgsEdit.TextHint := preset.Arguments;
    FNoteLabel.Caption := preset.AdapterClass.AdapterName + ' - ' + preset.Note;
  end
  else
    FNoteLabel.Caption := '';
end;

function TAIPlaneSettingsFrame.Busy: boolean;
begin
  Result := Assigned(FProbe);
end;

procedure TAIPlaneSettingsFrame.StartProbe(ATest: boolean);
var
  i: integer;
begin
  if Busy then
    Exit;
  FOutput.Clear;
  FProbeText := '';
  FProbeError := '';
  FProbeTesting := ATest;
  try
    FProbe := AICreateAdapter(GetRuntime, GetCommand, GetArguments);
  except
    on E: Exception do
    begin
      FStatusLabel.Caption := E.Message;
      Exit;
    end;
  end;
  FProbe.OnEvent := @ProbeEvent;
  FProbe.OnPermission := @ProbePermission;
  FProbe.WorkingDir := FWorkingDir;
  FProbe.Model := GetModel;
  FProbe.Effort := GetEffort;
  FDetectButton.Enabled := False;
  FTestButton.Enabled := False;
  FStatusLabel.Font.Color := clWindowText;
  FStatusLabel.Caption := 'Starting ' + FProbe.Command + ' ...';
  FProbeStarted := GetTickCount64;
  try
    if ATest then
      FProbe.Prompt(AIPLANE_TEST_PROMPT)
    else if Length(FProbe.Models) > 0 then
    begin
      // Fixed list, nothing to start.
      FModelBox.Items.Clear;
      for i := 0 to High(FProbe.Models) do
        FModelBox.Items.Add(FProbe.Models[i].Id);
      FinishProbe(Format('%d model(s)', [Length(FProbe.Models)]));
      Exit;
    end
    else
      FProbe.Start;
  except
    on E: Exception do
    begin
      FProbeError := E.Message;
      FinishProbe('');
      Exit;
    end;
  end;
  FTimer.Enabled := True;
end;

procedure TAIPlaneSettingsFrame.FinishProbe(const AMessage: string);
var
  probe: TAIAdapter;
begin
  FTimer.Enabled := False;
  probe := FProbe;
  FProbe := nil;
  if Assigned(probe) then
  begin
    probe.OnEvent := nil;
    probe.OnPermission := nil;
    probe.Stop;
    probe.Free;
  end;
  FDetectButton.Enabled := True;
  FTestButton.Enabled := True;
  if FProbeError <> '' then
  begin
    FStatusLabel.Font.Color := clRed;
    FStatusLabel.Caption := 'Failed: ' + FProbeError;
  end
  else
  begin
    FStatusLabel.Font.Color := clGreen;
    FStatusLabel.Caption := AMessage;
  end;
end;

procedure TAIPlaneSettingsFrame.ProbeEvent(Sender: TObject; const AEvent: TAIEvent);
begin
  case AEvent.Kind of
    aekText:
      FProbeText := FProbeText + AEvent.Text;
    aekStatus:
      FOutput.Lines.Add(AEvent.Text);
    aekError:
    begin
      FOutput.Lines.Add('error: ' + AEvent.Text);
      if FProbeError = '' then
        FProbeError := AEvent.Text;
    end;
    aekLog:
      if Copy(AEvent.Text, 1, 7) = 'stderr:' then
        FOutput.Lines.Add(AEvent.Text);
  end;
end;

procedure TAIPlaneSettingsFrame.ProbePermission(Sender: TObject;
  const ARequest: TAIPermissionRequest);
begin
  // The test prompt needs no tools; refuse anything it asks for.
  TAIAdapter(Sender).RespondPermission(ARequest.Key, '');
end;

procedure TAIPlaneSettingsFrame.TimerTick(Sender: TObject);
var
  i: integer;
  keep: string;
begin
  if not Assigned(FProbe) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  while FProbe.Poll do ;
  if not Assigned(FProbe) then
    Exit;

  if GetTickCount64 - FProbeStarted > AIPLANE_PROBE_TIMEOUT_MS then
  begin
    FProbeError := 'no answer within ' + IntToStr(AIPLANE_PROBE_TIMEOUT_MS div 1000) + ' s';
    FinishProbe('');
    Exit;
  end;

  if FProbe.State = aasFailed then
  begin
    if FProbeError = '' then
      FProbeError := 'runtime stopped';
    FinishProbe('');
    Exit;
  end;

  if Length(FProbe.Models) > 0 then
  begin
    keep := FModelBox.Text;
    FModelBox.Items.Clear;
    for i := 0 to High(FProbe.Models) do
      FModelBox.Items.Add(FProbe.Models[i].Id);
    FModelBox.Text := keep;
  end;

  if FProbeTesting then
  begin
    if FProbe.State = aasReady then
    begin
      FOutput.Lines.Add('');
      FOutput.Lines.Add('answer: ' + Trim(FProbeText));
      if FProbeError = '' then
        FinishProbe(Format('OK in %.1f s: %s', [(GetTickCount64 - FProbeStarted) / 1000,
          Copy(Trim(FProbeText), 1, 60)]))
      else
        FinishProbe('');
    end;
  end
  else if FProbe.State = aasReady then
    FinishProbe(Format('%d model(s) found', [Length(FProbe.Models)]));
end;

procedure TAIPlaneSettingsFrame.DetectModels;
begin
  StartProbe(False);
end;

procedure TAIPlaneSettingsFrame.RunTest;
begin
  StartProbe(True);
end;

procedure TAIPlaneSettingsFrame.RuntimeSelect(Sender: TObject);
begin
  FCommandEdit.Text := '';
  FArgsEdit.Text := '';
  FModelBox.Items.Clear;
  FModelBox.Text := '';
  UpdateNote;
  ValueChange(Sender);
  DetectModels;
end;

procedure TAIPlaneSettingsFrame.DetectClick(Sender: TObject);
begin
  DetectModels;
end;

procedure TAIPlaneSettingsFrame.TestClick(Sender: TObject);
begin
  RunTest;
end;

procedure TAIPlaneSettingsFrame.ValueChange(Sender: TObject);
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TAIPlaneSettingsFrame.GetRuntime: string;
begin
  if FRuntimeBox.ItemIndex < 0 then
    Result := ''
  else
    Result := AIPreset(FRuntimeBox.ItemIndex).Id;
end;

procedure TAIPlaneSettingsFrame.SetRuntime(const AValue: string);
var
  i: integer;
begin
  for i := 0 to AIPresetCount - 1 do
    if SameText(AIPreset(i).Id, AValue) then
      FRuntimeBox.ItemIndex := i;
  UpdateNote;
end;

function TAIPlaneSettingsFrame.GetCommand: string;
begin
  Result := Trim(FCommandEdit.Text);
end;

procedure TAIPlaneSettingsFrame.SetCommand(const AValue: string);
begin
  FCommandEdit.Text := AValue;
end;

function TAIPlaneSettingsFrame.GetArguments: string;
begin
  Result := Trim(FArgsEdit.Text);
end;

procedure TAIPlaneSettingsFrame.SetArguments(const AValue: string);
begin
  FArgsEdit.Text := AValue;
end;

function TAIPlaneSettingsFrame.GetModel: string;
begin
  Result := Trim(FModelBox.Text);
end;

procedure TAIPlaneSettingsFrame.SetModel(const AValue: string);
begin
  FModelBox.Text := AValue;
end;

function TAIPlaneSettingsFrame.GetEffort: string;
begin
  if FEffortBox.ItemIndex < 0 then
    Result := 'auto'
  else
    Result := FEffortBox.Items[FEffortBox.ItemIndex];
end;

procedure TAIPlaneSettingsFrame.SetEffort(const AValue: string);
var
  i: integer;
begin
  i := FEffortBox.Items.IndexOf(LowerCase(AValue));
  if i < 0 then
    i := 0;
  FEffortBox.ItemIndex := i;
end;

end.
