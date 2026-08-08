# LISP-to-LUAU

A Lisp dialect interpreter running inside Roblox. It has a reader (tokenizer + parser), a CEK machine evaluator with hygienic `syntax-rules` macros, and a Roblox interop layer that exposes engine APIs as Lisp builtins. Ships with a terminal GUI with server/client execution modes.

## Components

### Reader (`Reader.luau`)
Tokenizer and recursive-descent parser. Handles:
- S-expressions, quotes, strings with escapes
- Numbers (including negative), booleans (`#t`/`#f`), nil
- Comments (`;` to end of line)

### CEK Machine (`CEKMachine.luau`)
The evaluator. Key features:
- `syntax-rules` macros with pattern matching, literals, ellipsis (`...`), and gensym-based hygiene
- `defmacro` support
- Common Lisp-style lambda arguments: `&optional`, `&key`, `&rest`
- `call/cc` (call-with-current-continuation)
- Special forms: `define`, `lambda`, `if`, `begin`, `quote`, `quasiquote`, `set!`, `let`, `let*`, `letrec`, `named-let`, `cond`, `case`, `try`, `and`, `or`, `for`, `while`, `when`, `unless`, `struct`
- `--!strict` type checking enabled

### Environment (`Environment.luau`)
The global environment with builtins. Includes:
- Arithmetic: `+`, `-`, `*`, `/`, `%`, `^`
- Comparison: `=`, `<`, `>`, `<=`, `>=`, `~=`
- List ops: `cons`, `car`, `cdr`, `list`, `append`, `nth`, `filter`, `map`, `reduce`, `sort`, `zip`, `range`
- String ops: `string-append`, `string-length`, `string-ref`, `substring`, `string-upcase`, `string-downcase`, `string-split`, `string-trim`
- Higher-order: `apply`, `curry`, `compose`, `memoize`
- Roblox types: `vector3`, `vector2`, `cframe`, `color3`, `udim2`, `udim`, `rect`, `font`
- Vector/CFrame math: `vector3+`, `vector3-`, `vector3*`, `vector3-dot`, `vector3-cross`, `cframe*`, `cframe-lookAt`, `cframe-angles`
- Roblox APIs: `instance`, `service`, `connect`, `raycast`, `play-sound`, `tween`, `body-velocity`, `body-force`, `body-position`, `body-gyro`, `on-touched`, `once`
- DataStore: `data-store`, `data-set!`, `data-get`, `data-update!`, `data-remove!` (with mock fallback in Studio)
- HTTP: `http-get`, `http-post`, `http-get-async`
- Animation: `animator`, `load-animation`, `play-animation`, `stop-animation`
- Utility: `print`, `warn`, `wait`, `spawn`, `gensym`, `assert`, `time`, `printf`, `tostring`, `get-prop`, `disconnect`

### Runtime (`Runtime.luau`)
Glue layer. Parses Lisp code, evaluates via CEK machine, formats output as Lisp-style strings. Handles circular references and depth limits in printing.

### Server/Client bridge
- `ServerBridge.luau` — RemoteEvent server that executes Lisp code server-side
- `LocalScript.luau` — Terminal GUI with server/local execution modes, command history (Up/Down arrows), green-on-black terminal aesthetic

## Structure (Rojo)

```
ReplicatedStorage/LispMachine/
├── Reader.luau         — tokenizer + parser
├── CEKMachine.luau     — macro expander + CEK evaluator
├── Environment.luau    — builtins + Roblox interop
└── Runtime.luau        — execution glue + output formatting
ServerScriptService/
└── ServerBridge.luau   — RemoteEvent server
StarterGui/
└── LocalScript.luau    — terminal GUI
```

## Usage

Open in Roblox Studio. The terminal GUI lets you switch between server and local execution. Type Lisp code and press Enter.

```lisp
(define (factorial n)
  (if (= n 0) 1 (* n (factorial (- n 1)))))

(print (factorial 10))

(define part (instance "Part"))
(set! (get-prop part 'Position) (vector3 0 10 0))
```

## License

MIT
