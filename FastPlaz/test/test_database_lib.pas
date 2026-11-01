unit test_database_lib;

{
  TSimpleModel against a temporary SQLite database, so no server is needed.
  Requires the SQLite client library (sqlite3.dll / libsqlite3.so). When it
  cannot be loaded the whole suite is ignored; point SQLITE3_LIBRARY at the
  library file to use a specific one:

    set SQLITE3_LIBRARY=C:\path\to\sqlite3.dll
    run_tests.bat --suite=TSimpleModelSQLiteTest
}

{$mode objfpc}{$H+}

interface

uses
  database_lib, common, sqldb, sqlite3dyn, fpjson, Variants,
  Classes, SysUtils, fpcunit, testregistry;

type

  { TSimpleModelSQLiteTest }

  TSimpleModelSQLiteTest = class(TTestCase)
  private
    FDir: string;
    FDbFile: string;
    FModel: TSimpleModel;
    FSkipReason: string;
    procedure Connect;
    procedure Disconnect;
    procedure Exec(const ASQL: string);
    function CountRows: integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestReservedTableNameIsQuoted;
    procedure TestSaveAndDeleteFailuresReturnFalse;
    procedure TestConnected;
    procedure TestFieldListFromSqlite;
    procedure TestSaveInsertAndLastInsertID;
    procedure TestSaveTwiceSameFieldNoDuplicate;
    procedure TestSaveWithoutFields;
    procedure TestFindByIdAndUpdate;
    procedure TestUpdateWithoutRecordIsNoop;
    procedure TestFindWhereOrderLimit;
    procedure TestFindNoMatch;
    procedure TestFindStringKeyIsQuoted;
    procedure TestAllAndRecordCount;
    procedure TestAsJsonArray;
    procedure TestDeleteWhereAndById;
    procedure TestSoftDelete;
    procedure TestSelectWhereOrderByLimitOpen;
    procedure TestWhereWithFormat;
    procedure TestRecordsTotalFiltered;
    procedure TestQueryExecAndRowsAffected;
    procedure TestQueryOpenToJson;
    procedure TestValueOnClosedDataset;
  end;

implementation

const
  SCHEMA =
    'CREATE TABLE persons (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'name VARCHAR(50), ' +
    'age INTEGER, ' +
    'city VARCHAR(50), ' +
    'is_deleted INTEGER DEFAULT 0)';

procedure TSimpleModelSQLiteTest.Connect;
var
  lib: string;
begin
  lib := GetEnvironmentVariable('SQLITE3_LIBRARY');
  if lib <> '' then
    SQLiteDefaultLibrary := lib;
  FModel := TSimpleModel.Create('persons', 'id');
  with FModel.Connector do
  begin
    if Connected then
      Close;
    ConnectorType := 'SQLite3';
    DatabaseName := FDbFile;
    HostName := '';
    UserName := '';
    Password := '';
    try
      Open;
    except
      on E: Exception do
        FSkipReason := 'SQLite client library not available (' + E.Message + ')';
    end;
  end;
end;

procedure TSimpleModelSQLiteTest.Disconnect;
begin
  if Assigned(FModel) then
  begin
    try
      if FModel.Connector.Connected then
      begin
        if FModel.Connector.Transaction.Active then
          FModel.Connector.Transaction.Rollback;
        FModel.Connector.Close;
      end;
    except
    end;
    FreeAndNil(FModel);
  end;
end;

procedure TSimpleModelSQLiteTest.Exec(const ASQL: string);
begin
  FModel.Connector.ExecuteDirect(ASQL);
  FModel.Connector.Transaction.Commit;
end;

function TSimpleModelSQLiteTest.CountRows: integer;
var
  q: TSQLQuery;
begin
  q := TSQLQuery.Create(nil);
  try
    q.DataBase := FModel.Connector;
    q.SQL.Text := 'SELECT COUNT(*) AS n FROM persons';
    q.Open;
    Result := q.Fields[0].AsInteger;
    q.Close;
  finally
    q.Free;
  end;
end;

procedure TSimpleModelSQLiteTest.SetUp;
begin
  FSkipReason := '';
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'fastplaz_db_test_' +
    IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(FDir);
  FDbFile := FDir + 'test.sqlite';
  if FileExists(FDbFile) then
    DeleteFile(FDbFile);
  // the model reads these; keep read and write on the same connection
  AppData.databaseRead := 'default';
  AppData.databaseWrite := 'default';
  AppData.tablePrefix := '';
  AppData.debug := False;
  Connect;
  if FSkipReason <> '' then
  begin
    Disconnect;
    Ignore(FSkipReason);
  end;
  Exec(SCHEMA);
  Exec('INSERT INTO persons (name, age, city) VALUES (''Budi'', 30, ''Jakarta'')');
  Exec('INSERT INTO persons (name, age, city) VALUES (''Sari'', 25, ''Bandung'')');
  Exec('INSERT INTO persons (name, age, city) VALUES (''Tono'', 41, ''Jakarta'')');
end;

procedure TSimpleModelSQLiteTest.TearDown;
begin
  Disconnect;
  if FileExists(FDbFile) then
    DeleteFile(FDbFile);
  RemoveDir(ExcludeTrailingPathDelimiter(FDir));
end;

// generated SQL quotes the table and its alias: "order" (and "groups" on
// MySQL 8) are reserved words
procedure TSimpleModelSQLiteTest.TestReservedTableNameIsQuoted;
var
  m: TSimpleModel;
begin
  Exec('CREATE TABLE "order"(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
  m := TSimpleModel.Create('order', 'id');
  try
    AssertEquals('`order`', m.QuotedTableName);
    AssertEquals('`order`', m.QuotedAliasName);
    AssertEquals('`db`.`t`', m.QuoteIdentifier('db.t'));
    AssertEquals('t u', m.QuoteIdentifier('t u'));
    AssertEquals('`t`', m.QuoteIdentifier('`t`'));
    AssertEquals('', m.QuoteIdentifier(''));
    m.New;
    m['name'] := 'x';
    AssertTrue(m.Save);
    AssertTrue(m.Find([]));
    AssertEquals(1, m.RecordCount);
    AssertEquals('x', string(m['name']));
    AssertTrue(m.SQL.Text, Pos('FROM `order` `order`', m.SQL.Text) > 0);
    AssertTrue(m.SQL.Text, Pos('`order`.name', m.SQL.Text) > 0);
    AssertTrue(m.Find(['name=''x''']));
    AssertTrue(m.GetAll);
    AssertEquals(1, m.RecordCount);
    AssertTrue(m.Delete('id=1'));
    AssertFalse(m.Find([]));
  finally
    m.Free;
  end;
end;

// a failed INSERT/UPDATE/DELETE used to end the request through
// DisplayError; now the call returns False and Message says why, and the
// model stays usable
procedure TSimpleModelSQLiteTest.TestSaveAndDeleteFailuresReturnFalse;
var
  m: TSimpleModel;
begin
  Exec('CREATE TABLE uniq(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE)');
  m := TSimpleModel.Create('uniq', 'id');
  try
    m.New;
    m['code'] := 'a';
    AssertTrue(m.Save);
    AssertEquals('', m.Message);
    m.New;
    m['code'] := 'a';
    AssertFalse(m.Save);
    AssertTrue(m.Message, Pos('UNIQUE', UpperCase(m.Message)) > 0);
    // an unknown column
    m.New;
    m['nope'] := 'x';
    AssertFalse(m.Save);
    AssertTrue(m.Message <> '');
    // still usable afterwards
    m.New;
    m['code'] := 'b';
    AssertTrue(m.Save);
    AssertEquals('', m.Message);
    AssertTrue(m.Find([]));
    AssertEquals(2, m.RecordCount);
    // a bad DELETE
    AssertFalse(m.Delete('nope=1'));
    AssertTrue(m.Message <> '');
    AssertTrue(m.Delete('code=''b'''));
    AssertEquals('', m.Message);
    AssertTrue(m.Find([]));
    AssertEquals(1, m.RecordCount);
  finally
    m.Free;
  end;
end;

procedure TSimpleModelSQLiteTest.TestConnected;
begin
  AssertTrue(FModel.Connector.Connected);
  AssertEquals('persons', FModel.TableName);
  AssertEquals(3, CountRows);
end;

procedure TSimpleModelSQLiteTest.TestFieldListFromSqlite;
begin
  AssertEquals(5, FModel.FieldLists.Count);
  AssertEquals('persons.id', FModel.FieldLists[0]);
  AssertEquals('persons.name', FModel.FieldLists[1]);
end;

procedure TSimpleModelSQLiteTest.TestSaveInsertAndLastInsertID;
begin
  FModel.New;
  FModel['name'] := 'Dewi';
  FModel['age'] := 33;
  FModel['city'] := 'Surabaya';
  AssertTrue(FModel.Message, FModel.Save);
  AssertEquals(4, FModel.LastInsertID);
  AssertEquals(4, CountRows);
  AssertTrue(FModel.Find(4));
  AssertEquals('Dewi', string(FModel['name']));
  AssertEquals(33, Integer(FModel['age']));
end;

procedure TSimpleModelSQLiteTest.TestSaveTwiceSameFieldNoDuplicate;
begin
  FModel.New;
  FModel['name'] := 'first';
  FModel['name'] := 'second';
  FModel['age'] := 1;
  AssertTrue(FModel.Message, FModel.Save);
  AssertTrue(FModel.Find(FModel.LastInsertID));
  AssertEquals('second', string(FModel['name']));
end;

procedure TSimpleModelSQLiteTest.TestSaveWithoutFields;
begin
  FModel.New;
  AssertFalse(FModel.Save);
  AssertEquals('no field value to save', FModel.Message);
  AssertEquals(3, CountRows);
end;

procedure TSimpleModelSQLiteTest.TestFindByIdAndUpdate;
begin
  AssertTrue(FModel.Find(2));
  AssertEquals('Sari', string(FModel['name']));
  AssertEquals(1, FModel.RecordCount);
  FModel['age'] := 26;
  AssertTrue(FModel.Message, FModel.Update);
  AssertTrue(FModel.Find('2'));
  AssertEquals(26, Integer(FModel['age']));
  AssertEquals('other rows untouched', 3, CountRows);
end;

procedure TSimpleModelSQLiteTest.TestUpdateWithoutRecordIsNoop;
begin
  FModel.New;
  FModel['age'] := 99;
  // no Find before Update: must not run "UPDATE ... WHERE id="
  AssertFalse(FModel.Update);
  AssertTrue(FModel.Find(1));
  AssertEquals(30, Integer(FModel['age']));
end;

procedure TSimpleModelSQLiteTest.TestFindWhereOrderLimit;
begin
  AssertTrue(FModel.Find(['city=''Jakarta'''], 'age DESC'));
  AssertEquals(2, FModel.RecordCount);
  AssertEquals('Tono', string(FModel['name']));
  FModel.Next;
  AssertEquals('Budi', string(FModel['name']));
  FModel.Next;
  AssertTrue(FModel.EOF);

  AssertTrue(FModel.Find(['city=''Jakarta'''], 'age ASC', 1));
  AssertEquals(1, FModel.RecordCount);
  AssertEquals('Budi', string(FModel['name']));
end;

procedure TSimpleModelSQLiteTest.TestFindNoMatch;
begin
  AssertFalse(FModel.Find(['city=''Nowhere''']));
  AssertFalse(FModel.Find(999));
end;

// Find(string) used to concatenate the key into the WHERE clause
procedure TSimpleModelSQLiteTest.TestFindStringKeyIsQuoted;
var
  m: TSimpleModel;
begin
  Exec('INSERT INTO persons (name, age, city) VALUES (''O''''Brien'', 50, ''Dublin'')');
  // an injection attempt must not match every row
  AssertFalse(FModel.Find('1'' OR ''1''=''1'));
  AssertTrue(FModel.Find('3'));
  AssertEquals('Tono', string(FModel['name']));

  m := TSimpleModel.Create('persons', 'name');
  try
    AssertTrue(m.Find('O''Brien'));
    AssertEquals(1, m.RecordCount);
    AssertEquals('Dublin', string(m['city']));
    AssertFalse(m.Find('x'' OR name<>''x'));
  finally
    m.Free;
  end;
end;

procedure TSimpleModelSQLiteTest.TestAllAndRecordCount;
begin
  AssertTrue(FModel.All);
  AssertEquals(3, FModel.RecordCount);
  AssertTrue(FModel.GetAll(2));
  AssertEquals(2, FModel.RecordCount);
  AssertTrue(FModel.GetAll(2, 2));
  AssertEquals(1, FModel.RecordCount);
end;

procedure TSimpleModelSQLiteTest.TestAsJsonArray;
var
  a: TJSONArray;
begin
  AssertTrue(FModel.Find(['age > 26'], 'id'));
  a := FModel.AsJsonArray;
  try
    AssertEquals(2, a.Count);
    AssertEquals(2, FModel.RecordCountFromArray);
    AssertEquals('Budi', a.Objects[0].Strings['name']);
    AssertEquals(41, a.Objects[1].Integers['age']);
  finally
    a.Free;
  end;
  FModel.Close;
  a := FModel.AsJsonArray;
  try
    AssertEquals('closed dataset gives an empty array', 0, a.Count);
  finally
    a.Free;
  end;
end;

procedure TSimpleModelSQLiteTest.TestDeleteWhereAndById;
begin
  AssertTrue(FModel.Delete('city=''Bandung'''));
  AssertEquals(2, CountRows);
  AssertTrue(FModel.Delete(1));
  AssertEquals(1, CountRows);
  AssertTrue(FModel.Find(3));
end;

procedure TSimpleModelSQLiteTest.TestSoftDelete;
begin
  AssertTrue(FModel.SoftDelete(1));
  AssertEquals('row still there', 3, CountRows);
  AssertTrue(FModel.Find(1));
  AssertEquals(1, Integer(FModel['is_deleted']));
  FModel.UseSoftDelete := True;
  AssertTrue(FModel.All);
  AssertEquals('soft deleted rows hidden', 2, FModel.RecordCount);
end;

procedure TSimpleModelSQLiteTest.TestSelectWhereOrderByLimitOpen;
begin
  AssertTrue(FModel.Select('name, age').Where('age >= 25').OrderBy('age DESC').Limit(2).Open);
  AssertEquals(2, FModel.RecordCount);
  AssertEquals('Tono', string(FModel['name']));
  AssertTrue(Pos('ORDER BY age DESC', FModel.SQL.Text) > 0);
end;

procedure TSimpleModelSQLiteTest.TestWhereWithFormat;
begin
  AssertTrue(FModel.Where('city=%s', [QuotedStr('Bandung')]).Open);
  AssertEquals(1, FModel.RecordCount);
  AssertEquals('Sari', string(FModel['name']));
end;

procedure TSimpleModelSQLiteTest.TestRecordsTotalFiltered;
begin
  AssertEquals(2, FModel.RecordsTotalFiltered('SELECT COUNT(*) FROM persons WHERE city=''Jakarta'''));
  AssertEquals(0, FModel.RecordsTotalFiltered(''));
end;

procedure TSimpleModelSQLiteTest.TestQueryExecAndRowsAffected;
begin
  AssertTrue(QueryExec('UPDATE persons SET age = age + 1 WHERE city=''Jakarta'''));
  AssertEquals(2, QueryExecRowAffected);
  AssertFalse(QueryExec('UPDATE no_such_table SET x = 1'));
  AssertTrue(FModel.Find(1));
  AssertEquals(31, Integer(FModel['age']));
end;

procedure TSimpleModelSQLiteTest.TestQueryOpenToJson;
var
  o: TJSONObject;
  a: TJSONArray;
begin
  o := TJSONObject.Create;
  AssertTrue(QueryOpenToJson('SELECT name FROM persons ORDER BY id', o, False));
  try
    AssertEquals(3, o.Integers['count']);
    AssertEquals(3, o.Arrays['data'].Count);
    AssertEquals('Budi', o.Arrays['data'].Objects[0].Strings['name']);
  finally
    o.Free;
  end;
  a := TJSONArray.Create;
  AssertTrue(QueryOpenToJson('SELECT name FROM persons WHERE id=2', a, False));
  try
    AssertEquals(1, a.Count);
    AssertEquals('Sari', a.Objects[0].Strings['name']);
  finally
    a.Free;
  end;
end;

procedure TSimpleModelSQLiteTest.TestValueOnClosedDataset;
begin
  FModel.Close;
  AssertTrue(VarIsNull(FModel['name']) or VarIsEmpty(FModel['name']) or
    (string(FModel['name']) = ''));
  AssertEquals(-1, FModel.RecordCount);
  AssertTrue(FModel.EOF);
end;

initialization
  RegisterTest(TSimpleModelSQLiteTest);

end.
