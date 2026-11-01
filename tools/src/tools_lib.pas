unit tools_lib;

{
  Helpers shared by the FastPlaz IDE tools.

  This unit must not depend on the LCL or on the IDE interfaces so that it
  can be exercised by the console test suite in tools/src/test.
}

{$mode objfpc}{$H+}

interface

uses
  fpjson, jsonparser, Classes, SysUtils;

const
  DEFAULT_PROJECT_NAME = 'fastplaz';
  PROJECT_NAME_PLACEHOLDER = '%projectname%';
  HTACCESS_BINARY_PLACEHOLDER = 'your_binary_file';
  HTACCESS_ENVIRONMENT_PLACEHOLDER = '#environment';
  MODEL_CLASS_SUFFIX = 'Model';
  CONTROLLER_CLASS_SUFFIX = 'Controller';

// 'my project name' -> 'My Project Name'
function UcWords(const AText: string): string;

// Keeps only [A-Za-z0-9_], prefixes '_' when the result starts with a digit,
// appends '_' when the result is a reserved word and falls back to ADefault
// when nothing is left.
function SanitizeIdentifier(const AText: string;
  const ADefault: string = DEFAULT_PROJECT_NAME): string;

// Lower case identifier used for the program and its main unit.
function SanitizeProjectName(const AText: string;
  const ADefault: string = DEFAULT_PROJECT_NAME): string;

// Route key: lower case, spaces and '/' become '_', only [a-z0-9_-.] survive.
function SanitizePermalink(const AText: string): string;

// 'user group' -> 'TUserGroupController'
function ControllerTypeName(const AModuleName: string): string;

// 'user group' -> 'TUserGroupModel'
function ModelClassName(const AModelName: string): string;

// Mirrors TSimpleModel.Create(''): 'TUserGroupModel' -> 'user_groups'
function TableNameFromModelClass(const AClassName: string): string;

// Model name for a table of the database explorer.
// 'users' -> 'user' (TUserModel maps back to "users"),
// 'data' -> 'data' with ACustomTableName = 'data' because TDataModel would
// map to "datas"; the same for names that do not survive the lower case
// mapping ('Users').
procedure ModelNameFromTable(const ATableName: string;
  out AModelName, ACustomTableName: string);

// Recursive copy. %projectname% in file and directory names is replaced by
// AProjectName when it is not empty. Returns False when the source does not
// exist or when at least one file or directory could not be created; the
// remaining files are still copied.
function CopyDirectory(const ASourceDir, ATargetDir: string;
  const AProjectName: string = ''): boolean;

// One "SetEnvIf" line per header name, blank and invalid lines are skipped.
function HtaccessEnvironmentLines(AHeaders: TStrings): string;

// Fills the .htaccess template: binary name and (optional) header lines.
function BuildHtaccess(const ATemplate, ABinaryFile: string;
  AHeaders: TStrings = nil): string;

// Text of choices[0].message.content without markdown code fences.
// Returns '' when the response does not carry a text answer.
function FastCodeResponseText(const AResponseJSON: string): string;

implementation

const
  IDENTIFIER_CHARS = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  DIGITS = ['0'..'9'];
  HEADER_NAME_CHARS = ['A'..'Z', 'a'..'z', '0'..'9', '-', '_'];
  RESERVED_WORDS: array[0..31] of string = (
    'and', 'array', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'div', 'do', 'else', 'end', 'file', 'for', 'function', 'if',
    'implementation', 'interface', 'label', 'mod', 'nil', 'not', 'object', 'of',
    'or', 'procedure', 'program', 'record', 'set', 'type', 'unit', 'uses');

function UcWords(const AText: string): string;
var
  i: integer;
  upNext: boolean;
begin
  Result := LowerCase(AText);
  upNext := True;
  for i := 1 to Length(Result) do
  begin
    if Result[i] = ' ' then
      upNext := True
    else
    begin
      if upNext then
        Result[i] := UpCase(Result[i]);
      upNext := False;
    end;
  end;
  Result := Trim(Result);
end;

function IsReservedWord(const AText: string): boolean;
var
  i: integer;
  s: string;
begin
  s := LowerCase(AText);
  for i := Low(RESERVED_WORDS) to High(RESERVED_WORDS) do
    if s = RESERVED_WORDS[i] then
      Exit(True);
  Result := False;
end;

function SanitizeIdentifier(const AText: string; const ADefault: string): string;
var
  i: integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
    if AText[i] in IDENTIFIER_CHARS then
      Result := Result + AText[i];
  if Result = '' then
    Exit(ADefault);
  if Result[1] in DIGITS then
    Result := '_' + Result;
  if IsReservedWord(Result) then
    Result := Result + '_';
end;

function SanitizeProjectName(const AText: string; const ADefault: string): string;
begin
  Result := SanitizeIdentifier(LowerCase(Trim(AText)), ADefault);
end;

function SanitizePermalink(const AText: string): string;
var
  i: integer;
  s: string;
begin
  s := LowerCase(Trim(AText));
  s := StringReplace(s, ' ', '_', [rfReplaceAll]);
  s := StringReplace(s, '/', '_', [rfReplaceAll]);
  Result := '';
  for i := 1 to Length(s) do
    if s[i] in (IDENTIFIER_CHARS + ['-', '.']) then
      Result := Result + s[i];
end;

function ControllerTypeName(const AModuleName: string): string;
begin
  Result := 'T' + SanitizeIdentifier(StringReplace(UcWords(AModuleName), ' ', '',
    [rfReplaceAll]), 'Sample') + CONTROLLER_CLASS_SUFFIX;
end;

function ModelClassName(const AModelName: string): string;
begin
  Result := 'T' + SanitizeIdentifier(StringReplace(UcWords(AModelName), ' ', '',
    [rfReplaceAll]), 'Sample') + MODEL_CLASS_SUFFIX;
end;

function TableNameFromModelClass(const AClassName: string): string;
var
  i: integer;
begin
  // same loop as TSimpleModel.Create: skip the leading "T", put "_" before
  // every upper case letter, drop the "_model" suffix and append "s"
  Result := '';
  for i := 2 to Length(AClassName) do
  begin
    if AClassName[i] in ['A'..'Z'] then
    begin
      if Result <> '' then
        Result := Result + '_' + LowerCase(AClassName[i])
      else
        Result := Result + LowerCase(AClassName[i]);
    end
    else
      Result := Result + AClassName[i];
  end;
  Result := Copy(Result, 1, Length(Result) - Length('_' + MODEL_CLASS_SUFFIX)) + 's';
end;

procedure ModelNameFromTable(const ATableName: string;
  out AModelName, ACustomTableName: string);
var
  singular: string;
begin
  ACustomTableName := '';
  AModelName := ATableName;
  if (Length(ATableName) > 1) and (LowerCase(ATableName[Length(ATableName)]) = 's') then
  begin
    singular := Copy(ATableName, 1, Length(ATableName) - 1);
    if TableNameFromModelClass(ModelClassName(singular)) = ATableName then
    begin
      AModelName := singular;
      Exit;
    end;
  end;
  if TableNameFromModelClass(ModelClassName(ATableName)) <> ATableName then
    ACustomTableName := ATableName;
end;

function CopyFileContent(const ASource, ATarget: string): boolean;
var
  src, dst: TFileStream;
begin
  Result := False;
  try
    src := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
    try
      dst := TFileStream.Create(ATarget, fmCreate);
      try
        dst.CopyFrom(src, 0);
      finally
        dst.Free;
      end;
    finally
      src.Free;
    end;
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

function CopyDirectory(const ASourceDir, ATargetDir: string;
  const AProjectName: string): boolean;
var
  Rec: TSearchRec;
  sourceDir, targetDir, name: string;
begin
  sourceDir := IncludeTrailingPathDelimiter(ASourceDir);
  targetDir := IncludeTrailingPathDelimiter(ATargetDir);
  if not DirectoryExists(sourceDir) then
    Exit(False);
  Result := ForceDirectories(targetDir);
  if not Result then
    Exit;

  if FindFirst(sourceDir + '*', faAnyFile, Rec) = 0 then
  try
    repeat
      if (Rec.Name = '.') or (Rec.Name = '..') then
        Continue;
      name := Rec.Name;
      if AProjectName <> '' then
        name := StringReplace(name, PROJECT_NAME_PLACEHOLDER, AProjectName,
          [rfReplaceAll, rfIgnoreCase]);
      if (Rec.Attr and faDirectory) <> 0 then
        Result := CopyDirectory(sourceDir + Rec.Name, targetDir + name,
          AProjectName) and Result
      else
        Result := CopyFileContent(sourceDir + Rec.Name, targetDir + name) and Result;
    until FindNext(Rec) <> 0;
  finally
    FindClose(Rec);
  end;
end;

function IsHeaderName(const AName: string): boolean;
var
  i: integer;
begin
  if AName = '' then
    Exit(False);
  for i := 1 to Length(AName) do
    if not (AName[i] in HEADER_NAME_CHARS) then
      Exit(False);
  Result := True;
end;

function HtaccessEnvironmentLines(AHeaders: TStrings): string;
var
  i: integer;
  name: string;
  lines: TStringList;
begin
  Result := '';
  if AHeaders = nil then
    Exit;
  lines := TStringList.Create;
  try
    for i := 0 to AHeaders.Count - 1 do
    begin
      name := Trim(AHeaders[i]);
      if not IsHeaderName(name) then
        Continue;
      if lines.IndexOf(name) <> -1 then
        Continue;
      lines.Add(name);
    end;
    for i := 0 to lines.Count - 1 do
      Result := Result + Format('SetEnvIf %s "(.*)" %s=$1', [lines[i], lines[i]]) +
        LineEnding;
  finally
    lines.Free;
  end;
end;

function BuildHtaccess(const ATemplate, ABinaryFile: string;
  AHeaders: TStrings): string;
begin
  Result := StringReplace(ATemplate, HTACCESS_BINARY_PLACEHOLDER, ABinaryFile,
    [rfReplaceAll]);
  Result := StringReplace(Result, HTACCESS_ENVIRONMENT_PLACEHOLDER,
    TrimRight(HtaccessEnvironmentLines(AHeaders)), [rfReplaceAll]);
end;

function FastCodeResponseText(const AResponseJSON: string): string;
var
  data, content: TJSONData;
  lines: TStringList;
  i: integer;
begin
  Result := '';
  if Trim(AResponseJSON) = '' then
    Exit;
  try
    data := GetJSON(AResponseJSON);
  except
    on E: Exception do
      Exit;
  end;
  if data = nil then
    Exit;
  lines := TStringList.Create;
  try
    content := data.FindPath('choices[0].message.content');
    if (content = nil) or (content.JSONType <> jtString) then
      Exit;
    lines.Text := content.AsString;
    for i := lines.Count - 1 downto 0 do
      if Trim(lines[i]).StartsWith('```') then
        lines.Delete(i);
    Result := Trim(StringReplace(lines.Text, '```', '', [rfReplaceAll]));
  finally
    lines.Free;
    data.Free;
  end;
end;

end.
