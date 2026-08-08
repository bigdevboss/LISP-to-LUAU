# LISP-to-LUAU

A Lisp that runs inside Roblox. You hand it Lisp code and it evaluates it on the Luau runtime, with Roblox's own API wired straight in. So you can script a game in parentheses, call `workspace`, fire a `raycast`, or tween a part, all from Lisp.

I built it because I wanted a real language, not just a toy, running somewhere nobody expects one.

## What's actually in there

- **Reader** (`Reader.luau`): a tokenizer and recursive parser that turns source into an AST. Handles strings, numbers, quotes, and comments.
- **CEK machine** (`CEKMachine.luau`): the evaluator. It is a proper CEK abstract machine, the kind used for Scheme-like languages, with first-class continuations (`call/cc`), `eval`, and `apply`.
- **Lambda arguments**: `&optional`, `&key`, `&rest`, and plain varargs all work.
- **Hygienic macros**: `syntax-rules` with automatic renaming (gensym), so a macro's internal variables never collide with yours. Most hobby Lisps skip this. This one didn't.
- **Roblox glue**: builtins reach into `game`, `workspace`, `spawn`, `raycast`, `tween`, `instance`, `service`, `connect`, `play-sound`, `body-velocity`, and more. Plus the usual list and math operations.
- **Front end**: a `StarterGui` text box to type code and a `ServerScriptService` bridge.

## Try it

```lua
local Runtime = require(path.to.LispMachine.Runtime)
print(Runtime.execute([[
  (define (fib n)
    (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
  (fib 10)
]]))
-- prints 55
```

## Run it

Open the project in Roblox Studio. The `ReplicatedStorage/LispMachine`, `ServerScriptService`, and `StarterGui` folders map to Roblox services, so drop them in as-is. Then `require` the Runtime module and call `Runtime.execute(yourLispString)`. The GUI in `StarterGui` gives you a text box if you'd rather type than call functions.

## Notes

This is an interpreter hosted on Luau, not a source-to-source transpiler to Luau files, despite the repo name. The name stuck from an earlier idea.
