unit fastcode_configuration;

{$mode ObjFPC}{$H+}

interface

uses
  LazFileUtils, fpjson, openai_integration, thread_custom, IDEMsgIntf,
  IDEExternToolIntf, SrcEditorIntf, SynEdit, Classes, SysUtils, Forms, Controls,
  Graphics, Dialogs, ComCtrls, StdCtrls, ExtCtrls;

type

  { TfFastCodeConfiguration }

  TfFastCodeConfiguration = class(TForm)
    btnCancel: TButton;
    btnSave: TButton;
    btnTestConnection: TButton;
    cbbModel: TComboBox;
    edt_OpenAIBaseURL: TEdit;
    edt_OpeningChar: TEdit;
    edt_ClosingChar: TEdit;
    edt_Language: TEdit;
    edt_OpenAIKey: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    mem_Prompt: TMemo;
    Panel1: TPanel;
    procedure btnCancelClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnTestConnectionClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
  private
    sourceEditor: TSourceEditorInterface;
    selectedEditor: TSynEdit;
    FTestBaseURL: string;
    FTestKey: string;
    FTestError: string;
    FTestModels: TStringList;
    procedure DoTestConnection(Sender: TObject);
    procedure OnTestConnectionDone(Sender: TObject);
    procedure log(const Msg: string; AFileName: string = '';
      ATheUrgency: TMessageLineUrgency = mluNote);
  public
    Question: string;
    ResponseAsString: string;
    ResponseAsJson: TJSONData;
    destructor Destroy; override;
    procedure Prepare;
    procedure DoFastCode(Sender: TObject);
    procedure OnSuccessFastCode(Sender: TObject);
  end;

var
  fFastCodeConfiguration: TfFastCodeConfiguration;

function GetFastCodeSuggestion(AQuestion: string): string;
function NormalizeOpenAIBaseURL(const AUrl: string): string;

implementation

uses config_lib, de_common;

function NormalizeOpenAIBaseURL(const AUrl: string): string;
begin
  Result := AUrl.Trim;
  if Result.IsEmpty then
    Result := OPENAI_BASEURL
  else if not Result.EndsWith('/') then
    Result := Result + '/';
end;

function GetFastCodeSuggestion(AQuestion: string): string;
var
  openaiKey, openaiBaseURL, prompt: string;
begin
  Result := '';

  if AQuestion.IsEmpty then Exit;
  LoadConfiguration;
  openaiKey := GlobalConfig['fastcode/openai_api_key'];
  openaiBaseURL := GlobalConfig['fastcode/openai_base_url'];
  prompt := GlobalConfig['fastcode/prompt'];
  if openaiKey.IsEmpty and (NormalizeOpenAIBaseURL(openaiBaseURL) = OPENAI_BASEURL) then
  begin
    Result := 'OpenAI not found';
    ShowMessage('OpenAI Key not found. '#13'Please fill in the key from the "FastPlaz/Fast Code Configuration" menu');
    Exit;
  end;

  fFastCodeConfiguration.Question := AQuestion;
  fFastCodeConfiguration.edt_OpenAIKey.Text := openaiKey;
  fFastCodeConfiguration.edt_OpenAIBaseURL.Text := openaiBaseURL;
  fFastCodeConfiguration.cbbModel.Text := GlobalConfig['fastcode/openai_model'];
  fFastCodeConfiguration.mem_Prompt.Text := prompt;
  Call(@fFastCodeConfiguration.DoFastCode, @fFastCodeConfiguration.OnSuccessFastCode);

end;

{$R *.lfm}

{ TfFastCodeConfiguration }

procedure TfFastCodeConfiguration.FormCreate(Sender: TObject);
begin
  FTestModels := TStringList.Create;
  FTestModels.Sorted := True;
  FTestModels.Duplicates := dupIgnore;
end;

procedure TfFastCodeConfiguration.FormKeyDown(Sender: TObject;
  var Key: word; Shift: TShiftState);
begin
  if key = 27 then
  begin
    key := 0;
    Close;
  end;
end;

procedure TfFastCodeConfiguration.FormShow(Sender: TObject);
begin
end;

procedure TfFastCodeConfiguration.log(const Msg: string; AFileName: string;
  ATheUrgency: TMessageLineUrgency);
begin
  if IDEMessagesWindow <> nil then
    IDEMessagesWindow.AddCustomMessage(ATheUrgency, Msg, AFileName, 0, 0, 'FastPlaz');
end;

procedure TfFastCodeConfiguration.Prepare;
begin
  LoadConfiguration;
  edt_OpenAIBaseURL.Text := GlobalConfig['fastcode/openai_base_url'];
  edt_OpenAIKey.Text := GlobalConfig['fastcode/openai_api_key'];
  cbbModel.Text := GlobalConfig['fastcode/openai_model'];
  edt_Language.Text := GlobalConfig['fastcode/language'];
  mem_Prompt.Lines.Text := GlobalConfig['fastcode/prompt'];
  edt_OpeningChar.Text := GlobalConfig['fastcode/opening_char'];
  edt_ClosingChar.Text := GlobalConfig['fastcode/closing_char'];
end;

procedure TfFastCodeConfiguration.DoFastCode(Sender: TObject);
var
  prompt: string;
  msg: TJSONObject;
begin
  sourceEditor := SourceEditorManagerIntf.ActiveEditor;
  if sourceEditor = nil then Exit;
  if not (sourceEditor.EditorControl is TSynEdit) then Exit;
  selectedEditor := TSynEdit(sourceEditor.EditorControl);

  log('thingking ....');
  if Assigned(ResponseAsJson) then ResponseAsJson.Free;
  with TOpenAIIntegration.Create do
  begin
    BaseURL := NormalizeOpenAIBaseURL(edt_OpenAIBaseURL.Text);
    Key := edt_OpenAIKey.Text;
    if not Trim(cbbModel.Text).IsEmpty then
      Model := Trim(cbbModel.Text);
    prompt := mem_Prompt.Text;
    prompt := prompt.Replace('%language%', edt_Language.Text).Trim;
    if not prompt.IsEmpty then
    begin
      Messages.Clear;
      msg := TJSONObject.Create;
      msg.Add('role', 'system');
      msg.Add('content', prompt);
      Messages.Add(msg);
    end;

    // OnSyncStatus := @openAISync;
    ResponseAsString := '';
    if ChatCompletion(Question) then
    begin
      ResponseAsString := Response.AsJSON;
      ResponseAsJson := GetJSON(ResponseAsString, False);
    end;

    log('I get a response.');
    Free;
  end;

  // pengulangan dari 1 sampai 5

end;

procedure TfFastCodeConfiguration.OnSuccessFastCode(Sender: TObject);
var
  responseAsText: string;
begin
  log('formatting response...');
  if ResponseAsString.IsEmpty then
  begin
    log('Sorry, I can''t figure this out yet');
    Exit;
  end;

  try
    responseAsText := ResponseAsJson.GetPath('choices[0].message.content').AsJSON;
    responseAsText := responseAsText.Trim('"');
    responseAsText := responseAsText.Replace('```', '', [rfReplaceAll]);
    responseAsText := responseAsText.Replace('\n', #13, [rfReplaceAll]);
    responseAsText := responseAsText.Replace('\"', '"', [rfReplaceAll]);
    selectedEditor.InsertTextAtCaret(#13 + edt_OpeningChar.Text + #13 +
      responseAsText + #13 + edt_ClosingChar.Text + #13);
    log('done...');
  except
    on E: Exception do
    begin
      log('Failed, I got exception: ' + E.Message);
    end;
  end;

end;

procedure TfFastCodeConfiguration.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin

end;

procedure TfFastCodeConfiguration.btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure TfFastCodeConfiguration.btnSaveClick(Sender: TObject);
begin
  GlobalConfig['fastcode/openai_base_url'] := Trim(edt_OpenAIBaseURL.Text);
  GlobalConfig['fastcode/openai_api_key'] := edt_OpenAIKey.Text;
  GlobalConfig['fastcode/openai_model'] := Trim(cbbModel.Text);
  GlobalConfig['fastcode/language'] := edt_Language.Text;
  GlobalConfig['fastcode/prompt'] := mem_Prompt.Text;
  GlobalConfig['fastcode/opening_char'] := edt_OpeningChar.Text;
  GlobalConfig['fastcode/closing_char'] := edt_ClosingChar.Text;
  GlobalConfig.Flush;
  Close;
end;

procedure TfFastCodeConfiguration.btnTestConnectionClick(Sender: TObject);
begin
  // snapshot the UI values here; the worker thread must not touch controls
  FTestBaseURL := NormalizeOpenAIBaseURL(edt_OpenAIBaseURL.Text);
  FTestKey := Trim(edt_OpenAIKey.Text);
  FTestError := '';
  FTestModels.Clear;

  btnTestConnection.Enabled := False;
  btnTestConnection.Caption := 'Testing ...';
  log('testing connection to ' + FTestBaseURL);

  if not Call(@DoTestConnection, @OnTestConnectionDone) then
  begin
    FTestError := 'Unable to start the connection test thread';
    OnTestConnectionDone(nil);
  end;
end;

procedure TfFastCodeConfiguration.DoTestConnection(Sender: TObject);
var
  detail: string;
begin
  // runs in a worker thread
  with TOpenAIIntegration.Create do
  try
    BaseURL := FTestBaseURL;
    Key := FTestKey;
    try
      if not ListModels(FTestModels) then
      begin
        if not Assigned(HttpResult) then
          FTestError := 'No response from server'
        else
        begin
          detail := Trim(HttpResultAsText);
          if detail.Length > 300 then
            detail := detail.Substring(0, 300) + ' ...';
          FTestError := Format('HTTP %d', [HttpResult.ResultCode]);
          if not detail.IsEmpty then
            FTestError := FTestError + ': ' + detail;
        end;
      end;
    except
      on E: Exception do
        FTestError := E.Message;
    end;
  finally
    Free;
  end;
end;

procedure TfFastCodeConfiguration.OnTestConnectionDone(Sender: TObject);
var
  currentModel: string;
begin
  // runs in the main thread (synchronized)
  btnTestConnection.Enabled := True;
  btnTestConnection.Caption := '&Test Connection';

  if not FTestError.IsEmpty then
  begin
    log('connection failed: ' + FTestError, '', mluError);
    ShowMessage('Connection failed.'#13 + FTestError);
    Exit;
  end;

  currentModel := Trim(cbbModel.Text);
  cbbModel.Items.Assign(FTestModels);
  if currentModel.IsEmpty then
  begin
    if cbbModel.Items.Count > 0 then
      cbbModel.ItemIndex := 0;
  end
  else
    cbbModel.Text := currentModel;

  log(Format('connection ok, %d model(s) found', [FTestModels.Count]));
  ShowMessage(Format('Connection OK.'#13'%d model(s) found.', [FTestModels.Count]));
end;

destructor TfFastCodeConfiguration.Destroy;
begin
  FTestModels.Free;
  inherited Destroy;
end;

end.
