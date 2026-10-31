unit mailer_lib;

{$mode objfpc}{$H+}
{$include ../../define_fastplaz.inc}

interface

uses
  {$IFDEF SYNAPSE}
    {$IFDEF XMAILER}
  xmailer,
    {$ENDIF}
  {$ENDIF}
  Classes, SysUtils;

const
  _MAIL_NOSUPPORT = 'Mailer-Support not exist.';

// Format an address as "Name" <email>, or just email when Name is empty.
// CR/LF are stripped so a value cannot inject extra mail headers.
function FormatMailAddress(const Email: string; const Name: string = ''): string;
// Replace CR/LF in a header value (Subject, Sender, ...) with a space so a
// value cannot inject extra mail headers.
function SanitizeMailHeader(const S: string): string;

type

  { TMailer }
  TMailer = class
  private
    FErrorMessage: string;
    FMailServer: string;
    FMailPassword: string;
    FMailUserName: string;
    FPort: string;
    FTo, FCc, FBcc: TStringList;
    FEmailFormat: string;
    FLogs: string;
    FSSL, FTLS: boolean;
    function getEmailFormat: string;
    function getMailServer: string;
    function getSmtpPort: string;
    function getSSL: boolean;
    function getTLS: boolean;
    procedure setEmailFormat(AValue: string);
    procedure setMailPassword(AValue: string);
    procedure setMailServer(AValue: string);
    procedure setMailUserName(AValue: string);
    procedure setSmptPort(AValue: string);
    procedure setSSL(AValue: boolean);
    procedure setTLS(AValue: boolean);

    {$IFDEF XMAILER}
    procedure xmailer_OnProgress(const AProgress, AMax: integer; const AStatus: string);
    {$ENDIF XMAILER}
  public
    Subject, Sender: string;
    Message: TStringList;
    constructor Create(Setting: string = 'default');
    destructor Destroy; override;
    property emailFormat: string read getEmailFormat write setEmailFormat;
    property MailServer: string read getMailServer write setMailServer;
    property Port: string read getSmtpPort write setSmptPort;
    property UserName: string read FMailUserName write setMailUserName;
    property Password: string read FMailPassword write setMailPassword;
    property SSL: boolean read getSSL write setSSL;
    property TLS: boolean read getTLS write setTLS;
    property ErrorMessage: string read FErrorMessage;
    property Logs: string read FLogs;
    property Recipients: TStringList read FTo;
    property CcList: TStringList read FCc;
    property BccList: TStringList read FBcc;
    procedure AddTo(Email: string; Name: string = '');
    procedure AddCc(Email: string; Name: string = '');
    procedure AddBcc(Email: string; Name: string = '');
    procedure Clear;
    procedure Prepare;
    function Send: boolean;
  end;


implementation

uses common, config_lib;

function SanitizeMailHeader(const S: string): string;
begin
  Result := StringReplace(S, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function FormatMailAddress(const Email: string; const Name: string): string;
var
  cleanName: string;
begin
  Result := Trim(SanitizeMailHeader(Email));
  cleanName := Trim(SanitizeMailHeader(Name));
  if cleanName = '' then
    Exit;
  cleanName := StringReplace(cleanName, '\', '\\', [rfReplaceAll]);
  cleanName := StringReplace(cleanName, '"', '\"', [rfReplaceAll]);
  Result := '"' + cleanName + '" <' + Result + '>';
end;

{ TMailer }

procedure TMailer.AddTo(Email: string; Name: string);
begin
  FTo.Add(FormatMailAddress(Email, Name));
end;

procedure TMailer.AddCc(Email: string; Name: string);
begin
  FCc.Add(FormatMailAddress(Email, Name));
end;

procedure TMailer.AddBcc(Email: string; Name: string);
begin
  FBcc.Add(FormatMailAddress(Email, Name));
end;

procedure TMailer.Clear;
begin
  FTo.Clear;
  FBcc.Clear;
  FCc.Clear;
  FErrorMessage := '';
  FLogs := '';
  Subject := '';
  Message.Clear;
end;

procedure TMailer.Prepare;
begin
  Clear;
end;

function TMailer.Send: boolean;
{$IFDEF XMAILER}
var
  Mail: TSendMail;
{$ENDIF XMAILER}
begin
  Result := False;
  FErrorMessage := '';

  {$IFDEF XMAILER}
  Mail := TSendMail.Create;
  try
    try
      Mail.OnProgress := @xmailer_OnProgress;
      Mail.Smtp.Host := FMailServer;
      Mail.Smtp.Port := FPort;
      Mail.Smtp.UserName := FMailUserName;
      Mail.Smtp.Password := FMailPassword;
      Mail.Smtp.SSL := FSSL;
      Mail.Smtp.TLS := FTLS;

      Mail.Sender := Trim(SanitizeMailHeader(Sender));
      Mail.Receivers.Text := FTo.Text;
      Mail.CC.Text := FCc.Text;
      Mail.BCC.Text := FBcc.Text;
      Mail.Subject := Trim(SanitizeMailHeader(Subject));
      Mail.Message.Text := Message.Text;
      if FEmailFormat = 'html' then
        Mail.ContentType := ctTextHTML
      else
        Mail.ContentType := ctTextPlain;
      Mail.Send;
      FLogs := FLogs + 'OK';
      Result := True;
    except
      on e: Exception do
      begin
        FErrorMessage := e.Message;
        FLogs := FLogs + e.Message + #13;
      end;
    end;
  finally
    Mail.Free;
  end;
  {$ELSE}
  FErrorMessage := _MAIL_NOSUPPORT;
  FLogs := FLogs + _MAIL_NOSUPPORT + #13;
  {$ENDIF XMAILER}

end;

function TMailer.getMailServer: string;
begin
  Result := FMailServer;
end;

function TMailer.getEmailFormat: string;
begin
  Result := FEmailFormat;
end;

function TMailer.getSmtpPort: string;
begin
  Result := FPort;
end;

function TMailer.getSSL: boolean;
begin
  Result := FSSL;
end;

function TMailer.getTLS: boolean;
begin
  Result := FTLS;
end;

procedure TMailer.setEmailFormat(AValue: string);
begin
  FEmailFormat := AValue;
end;

procedure TMailer.setMailPassword(AValue: string);
begin
  if FMailPassword = AValue then
    Exit;
  FMailPassword := AValue;
end;

procedure TMailer.setMailServer(AValue: string);
begin
  if FMailServer = AValue then
    Exit;
  FMailServer := AValue;
end;

procedure TMailer.setMailUserName(AValue: string);
begin
  if FMailUserName = AValue then
    Exit;
  FMailUserName := AValue;
end;

procedure TMailer.setSmptPort(AValue: string);
begin
  if FPort = AValue then
    Exit;
  FPort := AValue;
end;

procedure TMailer.setSSL(AValue: boolean);
begin
  FSSL := AValue;
end;

procedure TMailer.setTLS(AValue: boolean);
begin
  FTLS := AValue;
end;

{$IFDEF XMAILER}
procedure TMailer.xmailer_OnProgress(const AProgress, AMax: integer;
  const AStatus: string);
begin
  FLogs := FLogs + FormatDateTime('YYYY-mm-dd hh:nn:ss', now) + ' | ' + AStatus + #13;
end;

{$ENDIF XMAILER}

constructor TMailer.Create(Setting: string);
begin
  FTo := TStringList.Create;
  FCc := TStringList.Create;
  FBcc := TStringList.Create;
  Message := TStringList.Create;
  FSSL := False;
  FTLS := False;
  FEmailFormat := 'html';
  FLogs := '';
  FErrorMessage := '';

  // read from config.json
  MailServer := Config[UTF8Decode(format(_MAIL_MAILSERVER, [Setting]))];
  UserName := Config[UTF8Decode(format(_MAIL_USERNAME, [Setting]))];
  Password := Config[UTF8Decode(format(_MAIL_PASSWORD, [Setting]))];
  Port := Config[UTF8Decode(format(_MAIL_SMTPPORT, [Setting]))];
  SSL := Config.GetValue(UTF8Decode(format(_MAIL_SSL, [Setting])), True);
  TLS := Config.GetValue(UTF8Decode(format(_MAIL_TLS, [Setting])), True);

end;

destructor TMailer.Destroy;
begin
  FreeAndNil(Message);
  FreeAndNil(FTo);
  FreeAndNil(FCc);
  FreeAndNil(FBcc);
  inherited Destroy;
end;

end.
