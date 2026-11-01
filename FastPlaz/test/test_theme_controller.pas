unit test_theme_controller;

{
  TThemeUtil without a web request: RenderFromContent() over string
  templates, the [if] processor, filters and the template name guard.
}

{$mode objfpc}{$H+}

interface

uses
  theme_controller, common, fpjson, Classes, SysUtils, fpcunit, testregistry;

type

  { TThemeControllerTest }

  TThemeControllerTest = class(TTestCase)
  private
    function Render(const AContent: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestIfTrueAndFalse;
    procedure TestIfElse;
    procedure TestIfMultilineHtml;
    procedure TestIfElseMultiline;
    procedure TestIfPercentBracesAndUnicode;
    procedure TestIfSingleLineFalseIsEmpty;
    procedure TestIfOperators;
    procedure TestIfQuotedValueWithSpaces;
    procedure TestIfNumericAgainstEmptyString;
    procedure TestIfUnknownVariableDropsBlock;
    procedure TestIfAssignedVariable;
    procedure TestIfNested;
    procedure TestIfSeveralBlocks;
    procedure TestIfUnclosedLeftAlone;
    procedure TestIfBadHeaderLeftAlone;
    procedure TestIfTagsSurviveTagController;
    procedure TestIfInsideForeachJson;
    procedure TestNl2brLineFeeds;
    procedure TestEmptyPipeFilter;
    procedure TestSafeTemplateName;
  end;

implementation

// RenderFromContent goes through TStringList.Text: line endings become the
// platform's and one is appended; normalise so the expectations are portable
function TThemeControllerTest.Render(const AContent: string): string;
begin
  Result := ThemeUtil.RenderFromContent(nil, AContent);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  if (Result <> '') and (Result[Length(Result)] = #10) then
    SetLength(Result, Length(Result) - 1);
end;

procedure TThemeControllerTest.SetUp;
begin
  AppData.debug := False;
  AppData.cacheTime := 3;
  ThemeUtil := TThemeUtil.Create;
  ThemeUtil.TrimWhiteSpace := False;
end;

procedure TThemeControllerTest.TearDown;
begin
  FreeAndNil(ThemeUtil);
end;

procedure TThemeControllerTest.TestIfTrueAndFalse;
begin
  ThemeUtil.Assign('a', '1');
  AssertEquals('yes', Render('[if a = 1]yes[/if]'));
  AssertEquals('', Render('[if a = 2]yes[/if]'));
  AssertEquals('x-yes-y', Render('x-[if a eq 1]yes[/if]-y'));
end;

procedure TThemeControllerTest.TestIfElse;
begin
  ThemeUtil.Assign('a', '1');
  AssertEquals('yes', Render('[if a = 1]yes[else]no[/if]'));
  AssertEquals('no', Render('[if a = 2]yes[else]no[/if]'));
end;

procedure TThemeControllerTest.TestIfMultilineHtml;
const
  tpl = '<ul>'#10'[if logged neq 0]'#10'  <li><a href="/logout">Logout</a></li>'#10'[/if]'#10'</ul>';
begin
  ThemeUtil.Assign('logged', '1');
  AssertEquals('<ul>'#10#10'  <li><a href="/logout">Logout</a></li>'#10#10'</ul>', Render(tpl));
  ThemeUtil.Assign('logged', '0');
  AssertEquals('<ul>'#10#10'</ul>', Render(tpl));
end;

procedure TThemeControllerTest.TestIfElseMultiline;
const
  tpl = '[if logged = 1]'#10'  <b>A</b>'#10'[else]'#10'  <i>B</i>'#10'[/if]';
begin
  ThemeUtil.Assign('logged', '1');
  AssertEquals(#10'  <b>A</b>'#10, Render(tpl));
  ThemeUtil.Assign('logged', '0');
  AssertEquals(#10'  <i>B</i>'#10, Render(tpl));
end;

procedure TThemeControllerTest.TestIfPercentBracesAndUnicode;
const
  body = '<div style="width:100%">Harga + ongkir ~ Rp 10.000 (promo) ♥ é</div>'
    + '<script>var x = {a: [1, 2]};</script>';
begin
  ThemeUtil.Assign('show', 'yes');
  AssertEquals(body, Render('[if show = "yes"]' + body + '[/if]'));
  AssertEquals('', Render('[if show = "no"]' + body + '[/if]'));
end;

procedure TThemeControllerTest.TestIfSingleLineFalseIsEmpty;
begin
  ThemeUtil.Assign('a', '2');
  // the old regex returned "ello World" here
  AssertEquals('', Render('[if a = 1]Hello World[/if]'));
end;

procedure TThemeControllerTest.TestIfOperators;
begin
  ThemeUtil.Assign('n', '5');
  ThemeUtil.Assign('s', 'abc');
  AssertEquals('t', Render('[if n neq 4]t[else]f[/if]'));
  AssertEquals('f', Render('[if n neq 5]t[else]f[/if]'));
  AssertEquals('t', Render('[if n != 4]t[else]f[/if]'));
  AssertEquals('t', Render('[if n <> 4]t[else]f[/if]'));
  AssertEquals('t', Render('[if n == 5]t[else]f[/if]'));
  AssertEquals('t', Render('[if n lt 6]t[else]f[/if]'));
  AssertEquals('f', Render('[if n lt 5]t[else]f[/if]'));
  AssertEquals('t', Render('[if n < 6]t[else]f[/if]'));
  AssertEquals('t', Render('[if n gt 4]t[else]f[/if]'));
  AssertEquals('t', Render('[if n > 4]t[else]f[/if]'));
  AssertEquals('t', Render('[if n lte 5]t[else]f[/if]'));
  AssertEquals('t', Render('[if n <= 5]t[else]f[/if]'));
  AssertEquals('f', Render('[if n lte 4]t[else]f[/if]'));
  AssertEquals('t', Render('[if n gte 5]t[else]f[/if]'));
  AssertEquals('t', Render('[if n >= 5]t[else]f[/if]'));
  AssertEquals('f', Render('[if n gte 6]t[else]f[/if]'));
  // an unquoted word on the right is a variable reference (empty here)
  AssertEquals('f', Render('[if s = abc]t[else]f[/if]'));
  AssertEquals('t', Render('[if s = "abc"]t[else]f[/if]'));
  AssertEquals('t', Render('[if s = ''abc'']t[else]f[/if]'));
  AssertEquals('f', Render('[if s = ""]t[else]f[/if]'));
  ThemeUtil.Assign('s', '');
  AssertEquals('t', Render('[if s = ""]t[else]f[/if]'));
  AssertEquals('t', Render('[if s eq '''']t[else]f[/if]'));
  AssertEquals('f', Render('[if s neq ""]t[else]f[/if]'));
end;

procedure TThemeControllerTest.TestIfQuotedValueWithSpaces;
begin
  ThemeUtil.Assign('title', 'Login Here');
  AssertEquals('t', Render('[if title = "Login Here"]t[else]f[/if]'));
  AssertEquals('f', Render('[if title = "Login There"]t[else]f[/if]'));
end;

procedure TThemeControllerTest.TestIfNumericAgainstEmptyString;
begin
  ThemeUtil.Assign('count', '');
  // must not raise EVariantError
  AssertEquals('f', Render('[if count gt 0]t[else]f[/if]'));
  AssertEquals('t', Render('[if count neq 0]t[else]f[/if]'));
end;

procedure TThemeControllerTest.TestIfUnknownVariableDropsBlock;
begin
  AssertEquals('a--b', Render('a-[if nothere = 1]yes[else]no[/if]-b'));
end;

procedure TThemeControllerTest.TestIfAssignedVariable;
var
  s: string;
begin
  // variable created by the [assign] tag (processed by the tag engine
  // before the [if] pass in Render), not by Assign()
  ThemeUtil.TagController(nil, 'assign var=level value=3', nil, s);
  AssertEquals('', s);
  AssertEquals('t', Render('[if level = 3]t[else]f[/if]'));
  AssertEquals('f', Render('[if level = 4]t[else]f[/if]'));
end;

procedure TThemeControllerTest.TestIfNested;
const
  tpl = '[if a = 1]A[if b = 1]B[else]b[/if]A[else]x[if b = 1]Y[else]y[/if]x[/if]';
begin
  ThemeUtil.Assign('a', '1');
  ThemeUtil.Assign('b', '1');
  AssertEquals('ABA', Render(tpl));
  ThemeUtil.Assign('b', '0');
  AssertEquals('AbA', Render(tpl));
  ThemeUtil.Assign('a', '0');
  AssertEquals('xyx', Render(tpl));
  ThemeUtil.Assign('b', '1');
  AssertEquals('xYx', Render(tpl));
end;

procedure TThemeControllerTest.TestIfSeveralBlocks;
begin
  ThemeUtil.Assign('a', '1');
  ThemeUtil.Assign('b', '2');
  AssertEquals('1-no-2', Render('[if a = 1]1[/if]-[if a = 2]yes[else]no[/if]-[if b = 2]2[/if]'));
end;

procedure TThemeControllerTest.TestIfUnclosedLeftAlone;
begin
  ThemeUtil.Assign('a', '1');
  AssertEquals('[if a = 1]open', Render('[if a = 1]open'));
  // the inner block is still evaluated
  AssertEquals('[if a = 1]outerin-', Render('[if a = 1]outer[if a = 1]in[/if]-'));
end;

procedure TThemeControllerTest.TestIfBadHeaderLeftAlone;
begin
  ThemeUtil.Assign('a', '1');
  AssertEquals('[if a]x[/if]', Render('[if a]x[/if]'));
  AssertEquals('[if a like 1]x[/if]', Render('[if a like 1]x[/if]'));
end;

procedure TThemeControllerTest.TestIfTagsSurviveTagController;
var
  s: string;
begin
  // Render() runs the tag engine before the [if] processor; the tags must
  // come out of it unchanged
  ThemeUtil.TagController(nil, 'if a = 1', nil, s);
  AssertEquals('[if a = 1]', s);
  ThemeUtil.TagController(nil, 'if title = "Login Here"', nil, s);
  AssertEquals('[if title = "Login Here"]', s);
  ThemeUtil.TagController(nil, 'else', nil, s);
  AssertEquals('[else]', s);
  ThemeUtil.TagController(nil, '/if', nil, s);
  AssertEquals('[/if]', s);
end;

procedure TThemeControllerTest.TestIfInsideForeachJson;
var
  data: TJSONArray;
  html: string;
begin
  data := TJSONArray.Create;
  try
    data.Add(TJSONObject.Create(['name', 'Budi', 'age', 30]));
    data.Add(TJSONObject.Create(['name', 'Sari', 'age', 17]));
    ThemeUtil.Assign('people', @data);
    html := Render('[foreach type=json from=people item=p]'
      + '<li>[p index=name][if p.age gte 18] (adult)[else] (minor)[/if]</li>'
      + '[/foreach from=people]');
    AssertEquals('<li>Budi (adult)</li><li>Sari (minor)</li>', html);
  finally
    data.Free;
  end;
end;

procedure TThemeControllerTest.TestNl2brLineFeeds;
begin
  ThemeUtil.Assign('txt', 'a'#13#10'b'#10'c'#13'd');
  AssertEquals('a<br>b<br>c<br>d', Render('[txt filter=nl2br]'));
end;

procedure TThemeControllerTest.TestEmptyPipeFilter;
begin
  ThemeUtil.Assign('x', 'v');
  // "[x|]" raised EStringListError (index 1 out of bounds)
  AssertEquals('v', Render('[x|]'));
  AssertEquals('V', Render('[x|uppercase]'));
end;

procedure TThemeControllerTest.TestSafeTemplateName;
begin
  AssertEquals('master', TThemeUtil.SafeTemplateName('master'));
  AssertEquals('detail', TThemeUtil.SafeTemplateName(' detail '));
  AssertEquals('', TThemeUtil.SafeTemplateName('../../etc/passwd'));
  AssertEquals('', TThemeUtil.SafeTemplateName('..\windows\win.ini'));
  AssertEquals('', TThemeUtil.SafeTemplateName('sub/page'));
  AssertEquals('', TThemeUtil.SafeTemplateName('C:x'));
  AssertEquals('', TThemeUtil.SafeTemplateName(''));
  AssertEquals('page', TThemeUtil.SafeTemplateName('page'#0'../x'));
end;

initialization
  RegisterTest(TThemeControllerTest);

end.
