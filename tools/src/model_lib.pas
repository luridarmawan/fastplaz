unit model_lib;

{$mode objfpc}{$H+}

interface

uses
  Forms, Dialogs, Controls, LazarusPackageIntf, ProjectIntf,
  Classes, SysUtils;

resourcestring
  rs_Model_Name = 'Database Model Generator';
  rs_Model_Description = 'create unit for model database';

type

  { TFileDescModel }

  TFileDescModel = class(TFileDescPascalUnit)
  private
    FClassName: string;
    FTableName: string;
  public
    constructor Create; override;
    function Init(var NewFilename: string; NewOwner: TObject;
      var NewSource: string; Quiet: boolean): TModalResult; override;
    function GetInterfaceUsesSection: string; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
    function GetInterfaceSource(
      const Filename, SourceName, ResourceName: string): string;
      override;
    function GetImplementationSource(
      const Filename, SourceName, ResourceName: string): string; override;
    function CreateSource(const Filename, SourceName, ResourceName: string): string;
      override;
  end;


var
  // set by the database explorer before DoNewEditorFile, reset by Init
  GenerateFromFDE: boolean = False;
  // explicit table name, '' when TSimpleModel can derive it from the class
  CustomTableName: string = '';
  // model name without the T prefix and the Model suffix, e.g. 'user group'
  ModelName: string;

implementation

uses
  fastplaz_tools_register, tools_lib, model_wzd;

const
  CS_DEFAULT_FILENAME = 'default_model.pas';
  CS_DEFAULT_SOURCENAME = 'modelname_model';

{ TFileDescModel }

constructor TFileDescModel.Create;
begin
  inherited Create;
  Name := 'Model Generator';
  DefaultFilename := CS_DEFAULT_FILENAME;
  DefaultSourceName := CS_DEFAULT_SOURCENAME;

  DefaultFileExt := '.pas';
  VisibleInNewDialog := True;
  IsPascalUnit := True;
end;

function TFileDescModel.Init(var NewFilename: string; NewOwner: TObject;
  var NewSource: string; Quiet: boolean): TModalResult;
var
  wizard: TfModelWizard;
begin
  Result := inherited Init(NewFilename, NewOwner, NewSource, Quiet);
  if Result <> mrOk then
    Exit;

  if GenerateFromFDE then
    GenerateFromFDE := False
  else if not bExpert then
  begin
    ModelName := 'Sample';
    CustomTableName := '';
    if not Quiet then
    begin
      wizard := TfModelWizard.Create(nil);
      try
        if wizard.ShowModal <> mrOk then
          Exit(mrCancel);
        if wizard.edt_ModelName.Text <> '' then
          ModelName := wizard.edt_ModelName.Text;
      finally
        wizard.Free;
      end;
    end;
  end;

  ModelName := SanitizeIdentifier(StringReplace(UcWords(ModelName), ' ', '',
    [rfReplaceAll]), 'Sample');
  FClassName := ModelClassName(ModelName);
  if CustomTableName = '' then
    FTableName := TableNameFromModelClass(FClassName)
  else
    FTableName := CustomTableName;
  if NewFilename = '' then
    NewFilename := LowerCase(ModelName) + '_model.pas';
end;

function TFileDescModel.GetInterfaceUsesSection: string;
begin
  Result := inherited GetInterfaceUsesSection;
  Result := Result + ', fpjson, database_lib, dateutils,'
    + LineEnding + '  string_helpers, datetime_helpers, array_helpers, json_helpers';
end;

function TFileDescModel.GetLocalizedName: string;
begin
  Result := rs_Model_Name;
end;

function TFileDescModel.GetLocalizedDescription: string;
begin
  Result := rs_Model_Description;
end;

function TFileDescModel.GetInterfaceSource(
  const Filename, SourceName, ResourceName: string): string;
var
  str: TStringList;
begin
  str := TStringList.Create;
  with str do
  begin
    Add('type');
    Add('');
    Add('{ ' + FClassName + ' }');
    Add('');
    Add('  ' + FClassName + ' = class(TSimpleModel)');
    Add('  private');
    Add('  public');
    Add('    constructor Create(const DefaultTableName: string = '''');');
    Add('  end;');
    Add('');
  end;
  Result := str.Text;
  FreeAndNil(str);
end;

function TFileDescModel.GetImplementationSource(
  const Filename, SourceName, ResourceName: string): string;
var
  str: TStringList;
begin
  Result := inherited GetImplementationSource(Filename, SourceName, ResourceName);
  str := TStringList.Create;
  with str do
  begin
    Add('uses common;');
    Add('');
    Add('constructor ' + FClassName + '.Create(const DefaultTableName: string = '''');');
    Add('Begin');
    if CustomTableName = '' then
    begin
      Add('  inherited Create( DefaultTableName); // table name = ' + FTableName);
      Add('  //inherited Create(''yourtablename''); // if use custom tablename');
    end
    else
    begin
      Add('  //inherited Create( DefaultTableName); // table name = ' +
        TableNameFromModelClass(FClassName));
      Add('  inherited Create(''' + StringReplace(FTableName, '''', '''''',
        [rfReplaceAll]) + '''); // custom tablename');
    end;
    Add('End;');
    Add('');
  end;
  Result := Result + str.Text;
  FreeAndNil(str);
end;

function TFileDescModel.CreateSource(
  const Filename, SourceName, ResourceName: string): string;
begin
  Result := inherited CreateSource(Filename, SourceName, FClassName);
  log('model "' + FClassName + '" created', Filename);
end;

end.
