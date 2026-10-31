unit test_mailer_lib;

{$mode objfpc}{$H+}
{$include define_fastplaz.inc}

interface

uses
  mailer_lib, Classes, SysUtils, fpcunit, testregistry;

type

  { TMailerLibTest }

  TMailerLibTest = class(TTestCase)
  published
    procedure TestFormatAddressPlain;
    procedure TestFormatAddressWithName;
    procedure TestFormatAddressQuotesInName;
    procedure TestFormatAddressStripsCRLF;
    procedure TestSanitizeHeader;
    procedure TestAddToCcBccGoToSeparateLists;
    procedure TestClearResetsLists;
    procedure TestSendWithoutSupportReportsError;
    procedure TestCreateAndFree;
  end;

implementation

procedure TMailerLibTest.TestFormatAddressPlain;
begin
  AssertEquals('a@b.c', FormatMailAddress('a@b.c'));
  AssertEquals('a@b.c', FormatMailAddress(' a@b.c ', ''));
end;

procedure TMailerLibTest.TestFormatAddressWithName;
begin
  AssertEquals('"Budi Santoso" <a@b.c>', FormatMailAddress('a@b.c', 'Budi Santoso'));
  AssertEquals('"Budi" <a@b.c>', FormatMailAddress('a@b.c', '  Budi  '));
end;

procedure TMailerLibTest.TestFormatAddressQuotesInName;
begin
  AssertEquals('"Budi \"B\" S" <a@b.c>', FormatMailAddress('a@b.c', 'Budi "B" S'));
  AssertEquals('"back\\slash" <a@b.c>', FormatMailAddress('a@b.c', 'back\slash'));
end;

procedure TMailerLibTest.TestFormatAddressStripsCRLF;
begin
  AssertEquals('"Evil Bcc: x@y.z" <a@b.c>',
    FormatMailAddress('a@b.c', 'Evil' + #13#10 + 'Bcc: x@y.z'));
  AssertEquals('a@b.c X-Injected: 1', FormatMailAddress('a@b.c' + #10 + 'X-Injected: 1'));
end;

procedure TMailerLibTest.TestSanitizeHeader;
begin
  AssertEquals('Hello', SanitizeMailHeader('Hello'));
  AssertEquals('Hello World', SanitizeMailHeader('Hello' + #13#10 + 'World'));
  AssertEquals('a b c', SanitizeMailHeader('a' + #13 + 'b' + #10 + 'c'));
  AssertEquals(' ', SanitizeMailHeader(#13#10));
end;

procedure TMailerLibTest.TestAddToCcBccGoToSeparateLists;
var
  m: TMailer;
begin
  m := TMailer.Create;
  try
    m.AddTo('to@x.y', 'To');
    m.AddCc('cc@x.y');
    m.AddBcc('bcc1@x.y');
    m.AddBcc('bcc2@x.y', 'Two');
    AssertEquals(1, m.Recipients.Count);
    AssertEquals('"To" <to@x.y>', m.Recipients[0]);
    AssertEquals(1, m.CcList.Count);
    AssertEquals('cc@x.y', m.CcList[0]);
    AssertEquals(2, m.BccList.Count);
    AssertEquals('"Two" <bcc2@x.y>', m.BccList[1]);
  finally
    m.Free;
  end;
end;

procedure TMailerLibTest.TestClearResetsLists;
var
  m: TMailer;
begin
  m := TMailer.Create;
  try
    m.AddTo('to@x.y');
    m.AddCc('cc@x.y');
    m.AddBcc('bcc@x.y');
    m.Subject := 'S';
    m.Message.Add('body');
    m.Clear;
    AssertEquals(0, m.Recipients.Count);
    AssertEquals(0, m.CcList.Count);
    AssertEquals(0, m.BccList.Count);
    AssertEquals('', m.Subject);
    AssertEquals(0, m.Message.Count);
    AssertEquals('', m.ErrorMessage);
  finally
    m.Free;
  end;
end;

procedure TMailerLibTest.TestSendWithoutSupportReportsError;
var
  m: TMailer;
begin
  {$IFDEF XMAILER}
  Ignore('xmailer is compiled in; Send would contact an SMTP server');
  {$ELSE}
  m := TMailer.Create;
  try
    m.AddTo('to@x.y');
    AssertFalse(m.Send);
    AssertEquals(_MAIL_NOSUPPORT, m.ErrorMessage);
    AssertTrue(Pos(_MAIL_NOSUPPORT, m.Logs) > 0);
  finally
    m.Free;
  end;
  {$ENDIF}
end;

procedure TMailerLibTest.TestCreateAndFree;
var
  i: integer;
  m: TMailer;
begin
  for i := 1 to 20 do
  begin
    m := TMailer.Create('other');
    AssertEquals('html', m.emailFormat);
    m.Free;
  end;
end;

initialization
  RegisterTest(TMailerLibTest);

end.
