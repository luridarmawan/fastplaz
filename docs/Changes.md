# Development Changes

## 20261102

New Feature/Library:
- model: `ExecScript`, `QueryExecScript`, `ExecSQLScript` run a multi-statement SQL script (SQLite and MySQL `ExecuteDirect` take one statement per call) in one transaction, rolled back on the first failure
- model: `SplitSQLStatements` splits a script on `;` outside quotes, comments, `$tag$` bodies and trigger `BEGIN..END` blocks
- tools: FastPlaz > Open Console/Terminal and editor popup Open Terminal from Here

Bug Fix:
- model: `Find(string)` quotes the key value
- regexpr: include file renamed `regexpr_compilers_lib.inc` (duplicate file warning with LazEdit when rebuilding the IDE)

## 20261101

Review and fix pass over `FastPlaz/src` and `tools/src`, with an FPCUnit suite for every library unit. Read [UPGRADE.md](UPGRADE.md) before upgrading: some changes alter how an application behaves.

Behaviour changes:
- session: timeout is in minutes (the 3 day default expired after 72 minutes); default directory `<TEMP>/sessions`
- model: a failed `Save`/`Delete`/`SoftDelete` returns False with `Message` instead of ending the request
- theme: `[flashmessages]` is HTML encoded, `[flashmessages html=1]` keeps markup
- common: `X-Forwarded-For`/`Client-IP` are only used with `systems/trust_proxy`
- recaptcha: v1 API removed, the widget is always v2
- integration: discontinued services marked deprecated (bmkg, clarifai, googleanalytics, kloudless, newrelic, office365, yandex, zomato)

New Feature/Library:
- model: `QuoteIdentifier`, `QuoteValue`, quoted table and alias names, `SoftDelete`
- theme: `escape` filter, rewritten `[if]`, nested `[foreach]`, per-session page cache
- session: `RegenerateID`, HttpOnly/SameSite/Secure cookie
- html: one CSRF token per form, constant time comparison
- mailer: built-in SMTP client (`smtp_lib`), Cc/Bcc, `HeloName`
- redis: IPv6, full RESP parsing, connect timeout
- tools: name sanitising in the wizards, Database Explorer port and prefix, Fast Code for OpenAI-compatible servers

Bug Fix:
- handler: code after `die()` no longer runs during initialisation, 405 on unsupported method, CORS with credentials, header line breaks stripped
- cms/app: compile again, exit after `Redirect`, SQL values quoted, CSRF checked
- integration: destructors run (30 classes were missing `override`), responses no longer shared between calls
- many leaks, double frees, XXE in rss_lib, endless loops in StripTags and the Nazief stemmer

## 20231222.1419


New Feature/Library:
- vocal/consonant determinator
- integration: dotid whois support
- helper: add and remove slash
- helper: quoted string
- theme: search include file from basepath

Bug Fix:
- session: change session lastused field to unixtime format
- fix markup converter
- parsing form data with regex
- datatojson: smallint & largeint support and unknown field type
- fix post header; fix wording function

## 20210608.1111

- handler: float to string format
- handler: whois handler for .id domain
- handler: OutputJson with json utils
- theme: foreach for json data
- filter: unix2date with format
- filter: number with format

## 20201218.1424

- Session with custom UniqueID 

## 20201206.0001

- Reveal File in Explorer/Finder

## 20201205.1405

- Tools: JSON Visualization (TreeView)
- FDE: Load custom DB Library
- Bug: release secondary db memory

## 20201203.0344

- Tools: Database Explorer
- Tools: Json Formatter & Validator
- Tools: Regex Tester
- config lib: set json data value

## 20201124.2145

- url routing with group name regex
- api test doc
- Add action file templates
- Add last_update files
- Action: updater
- Change version number

## 20201122.0923

- Add changes document
- Contact & login example
- Bug: ConditionalProcessor cannot executed in Foreach bug 
- Force rename theme "Simple"
- Fix error page; check db connection before saving
- Readme & environment
- Tambah informasi database-example yg lebih kompleks
- File upload example
- Form example & dashboard theme


## 20201121.0927

- DB: check db connection
- Fix error page
- Readme: add docs url
- Add [baseurl] to template
- Add global variabel: Environment
- Tambah informasi kompleks database-example 
- File upload example
- Dashboard theme template

## undocumented changes 

....
