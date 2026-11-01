program tools_test;

{$mode objfpc}{$H+}

uses
  Classes, consoletestrunner, fastplaz_testrunner, test_regex_tester_lib, test_tools_lib;

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
  App.Title := 'FastPlaz Tools Test';
  App.Run;
  App.Free;
end.
