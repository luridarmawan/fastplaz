program fastplaz_test;

{$mode objfpc}{$H+}

uses
  Classes, consoletestrunner, test_datetime_lib, test_redis_lib,
  test_json_lib, test_config_lib, test_common;

type

  { TMyTestRunner }

  TMyTestRunner = class(TTestRunner)
  protected
  end;

var
  App: TMyTestRunner;

begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  App := TMyTestRunner.Create(nil);
  App.Initialize;
  App.Title := 'FastPlaz - Library Test';
  App.Run;
  App.Free;
end.
