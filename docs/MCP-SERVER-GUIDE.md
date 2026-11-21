# MCP Server in a FastPlaz Application

A FastPlaz application can be an **MCP (Model Context Protocol) server**:
AI agents and MCP clients (Claude Code, Claude Desktop, MCP Inspector,
OpenCode, ...) discover its tools and call them over HTTP. The same binary
serves MCP as a standalone HTTP server or as CGI behind Apache.

This page is about MCP servers you build *with* FastPlaz. The MCP server
inside the Lazarus IDE (AI Agent Plane) is described in [MCP.md](MCP.md).

| Item | Value |
| --- | --- |
| Endpoint | `POST /mcp`, one JSON-RPC message per request, JSON answer |
| Transport | MCP Streamable HTTP without SSE; `GET /mcp` answers `405` |
| Session | stateless, no `Mcp-Session-Id`; works the same in CGI and standalone mode |
| Protocol versions | `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05` |
| Methods | `initialize`, `ping`, `tools/list`, `tools/call`, `resources/list`, `resources/read`, `resources/templates/list`, `prompts/list` (empty) |
| Units | `FastPlaz/src/mcp/mcp_server.pas` (protocol core), `FastPlaz/src/mcp/mcp_handler.pas` (controller) |

## Create a project

In Lazarus:

- **File > New ... > FastPlaz > MCP Server Application** creates a complete
  project: program, `routes.pas` with `Route['mcp']`, a controller with an
  example `hello` tool, the web directory structure, an `mcp` section in
  `config/config.json` and an `.htaccess` that passes the bearer token to
  the CGI program.
- **FastPlaz > Create MCP Controller** adds an MCP endpoint to an existing
  project.

Without the wizard, use the `fastplaz_runtime` package (or add
`FastPlaz/src/mcp` to the unit path) and route the controller:

```pascal
uses mcp_handler;

initialization
  Route['mcp'] := TMcpController;   // POST /mcp
```

A complete example is in [examples/mcp](../examples/mcp).

## Add a tool

Register tools in the `initialization` section of any unit the program
uses. The handler gets a `TMcpToolCall` with the arguments and writes the
result into it.

```pascal
uses mcp_server;

procedure DoGreet(ACall: TMcpToolCall);
begin
  if ACall.Str('name') = '' then
    raise EMcpToolError.Create('name is required');
  ACall.Finish('Hello ' + ACall.Str('name'));
end;

initialization
  McpServer.Name := 'greeter';           // serverInfo sent at initialize
  McpServer.Version := '1.0.0';
  McpServer.RegisterTool('greet', 'Greet', 'Says hello to someone.',
    '{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}',
    @DoGreet, [mthReadOnly]);
```

`RegisterTool(Name, Title, Description, InputSchema, Handler, Hints, OutputSchema)`:

| Parameter | Notes |
| --- | --- |
| `Name` | 1-128 characters of `A-Z a-z 0-9 _ - .` |
| `Description` | what the agent reads to decide when to call the tool; be specific |
| `InputSchema` | JSON Schema of the arguments; `''` means no arguments |
| `Handler` | a procedure or a method (`of object`) |
| `Hints` | annotations: `mthReadOnly`, `mthDestructive`, `mthIdempotent`, `mthOpenWorld` |
| `OutputSchema` | optional JSON Schema of a structured result (see `FinishJSON`) |

### Reading arguments

| Method | Returns |
| --- | --- |
| `Has(name)` | the argument is present |
| `Str(name, default)` | string |
| `Int(name, default)` | int64 |
| `Float(name, default)` | double |
| `Bool(name, default)` | boolean |
| `Args` | the whole arguments object (`TJSONObject`, never nil) |

### Answering

| Method | Result |
| --- | --- |
| `Finish(text)` | adds a text content item; call it more than once for several items |
| `FinishJSON(data)` | sends JSON as text, and as `structuredContent` when `data` is an object; takes ownership of `data` |
| `Fail(message)` | tool error (`isError: true`), the agent reads the message |
| `raise EMcpToolError.Create(message)` | same as `Fail` |

Any other exception becomes a tool error with a generic text, so internal
details (SQL, paths) do not leak to the client. Set `exception_details` in
the config, or `McpServer.ExceptionDetails := True`, while developing.
`McpServer.OnError` receives those exceptions for logging.

### Structured result

```pascal
procedure DoAdd(ACall: TMcpToolCall);
begin
  ACall.FinishJSON(TJSONObject.Create(['sum', ACall.Float('a') + ACall.Float('b')]));
end;

initialization
  McpServer.RegisterTool('add', 'Add numbers', 'Adds two numbers.',
    '{"type":"object","properties":{"a":{"type":"number"},"b":{"type":"number"}},"required":["a","b"]}',
    @DoAdd, [mthReadOnly, mthIdempotent],
    '{"type":"object","properties":{"sum":{"type":"number"}},"required":["sum"]}');
```

## Add a resource

A resource is a text the client can read by URI. The handler is asked for
the text on every read; return `False` with a reason when it cannot be read.

```pascal
function ReadAbout(const AUri: string; out AText: string): boolean;
begin
  AText := '# My server' + LineEnding + 'Tools: greet, add.';
  Result := True;
end;

initialization
  McpServer.RegisterResource('myapp://about', 'about', 'About this server',
    'What this server offers', 'text/markdown', @ReadAbout);
```

`McpServer.Instructions` is sent to the client at `initialize`; agents use
it as a short guide to the server.

## Threads and state

In standalone mode the server answers requests in several threads with one
`McpServer`:

- register tools and resources in `initialization` sections only; the
  registry is only read afterwards;
- keep tool handlers free of shared state, or protect it with a lock;
- open a database connection per call (or use the FastPlaz per-request
  connection) instead of sharing one object between threads.

In CGI mode every request is a new process, so nothing is kept between
calls either way. Do not rely on state between two tool calls.

## Configuration

`config/config.json`, read once on the first request. Only keys that are
present change what the code set.

```json
"mcp" : {
  "token" : "env:MCP_TOKEN",
  "allowed_origins" : "app.example.com",
  "exception_details" : false
}
```

| Key | Meaning |
| --- | --- |
| `token` | every request must send `Authorization: Bearer <token>`; `env:NAME` reads the token from the environment variable `NAME`; `""` = no token |
| `allowed_origins` | browser origins allowed besides loopback and the server's own host, separated by comma or space; `*` allows every origin |
| `exception_details` | send the text of unexpected exceptions to the client (development only) |

The same settings in code: `McpServer.Token`, `McpServer.AllowedOrigins`,
`McpServer.ExceptionDetails`.

Checks done on every HTTP request, in this order:

1. `Origin`: a request with an `Origin` header from another site is refused
   with `403` (protection against DNS rebinding from a browser); MCP clients
   that are not browsers send no `Origin`;
2. token: a missing or wrong token answers `401` (compared in constant time);
3. method: only `POST`; `GET` and the others answer `405`;
4. `MCP-Protocol-Version` header: an unknown version answers `400`.

A server reachable from outside your machine should always have a token.

## Run it

### Standalone

```
./myapp.bin
```

The endpoint is `http://127.0.0.1:17845/mcp` (or the `port` in
`systems/server` of `config.json`, or `--port=`).

### CGI behind Apache

The binary runs as CGI as soon as Apache starts it. Apache does **not**
pass the `Authorization` header to CGI programs, so the bearer token never
arrives. The `.htaccess` made by the wizard passes it with a rewrite rule:

```apache
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
```

The controller reads it as `HTTP_AUTHORIZATION` or
`REDIRECT_HTTP_AUTHORIZATION`. `CGIPassAuth On` (Apache 2.4.13+) does the
same, but in `.htaccess` it needs `AllowOverride AuthConfig`; without it
Apache answers `500`.

### Compile from the console

```
lazbuild myapp.lpi
```

A project compiled with `fpc` and an `extra.cfg` instead of the package
needs `-Fu<fastplaz>/FastPlaz/src/mcp` next to the other FastPlaz unit
paths.

## Connect a client

### Claude Code

```
claude mcp add --transport http myapp http://127.0.0.1:17845/mcp
claude mcp add --transport http myapp http://127.0.0.1:17845/mcp --header "Authorization: Bearer <token>"
```

or in `.mcp.json`:

```json
{
  "mcpServers": {
    "myapp": {
      "type": "http",
      "url": "http://127.0.0.1:17845/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

### MCP Inspector

```
npx @modelcontextprotocol/inspector
```

Choose transport **Streamable HTTP** and the URL `http://127.0.0.1:17845/mcp`.

### curl

```
curl -s -X POST http://127.0.0.1:17845/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

curl -s -X POST http://127.0.0.1:17845/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"greet","arguments":{"name":"Budi"}}}'
```

## Limits

- No SSE stream: no progress notifications and no server-initiated
  messages (sampling, elicitation).
- No sessions: every request stands alone.
- No stdio transport yet; clients connect over HTTP.
- Authentication is a static bearer token, not the MCP OAuth flow.
- Only text resources; prompts are not supported (`prompts/list` is empty).
