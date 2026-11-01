program regex_tester_test;

{$mode objfpc}{$H+}

uses
  Classes, consoletestrunner, fastplaz_testrunner, test_regex_tester_lib;

type

  { TMyTestRunner }

  TMyTestRunner = class(TFastPlazTestRunner)
  protected
  end;

var
  App: TMyTestRunner;

begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  App := TMyTestRunner.Create(nil);
  App.Initialize;
  App.Title := 'FastPlaz Tools - Regex Tester Test';
  App.Run;
  App.Free;
end.
