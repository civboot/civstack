# Architecture

Ele is architected using the MVI (model-view-intent) architecture, also known as
the "React architecture" from the web library of the same name.


```
   ,_____________________________________________
   | intent(): keyboard, timer, executor, etc    |
   `~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'
   /\                                    || Data + events
   || Data + scheduled                   \/
  ,__________________   Data + scheduled ,____________________________
  | view(): paint    | <================ | model(): keybind, actions  |
  `~~~~~~~~~~~~~~~~~~'                   `~~~~~~~~~~~~~~~~~~~~~~~~~~~~'
```

The update loop (displayed above) is as follows:
* Receive a single intent: this can be a keyboard input, a timer firing or an
  operation function (async function) completing.
* Execute the model action tied to that event: aka the keybinding or a
  registered action. This will mutate Data depending on the event. It may also
  spawn some async opfns (operation functions)
* Paint the view/s (user-visible) and await the next intent

## Data
Data holds almost all the "state" for the application, as well as helper
methods. This includes:
* The `bufs` which has all open buffers
* The `root` View (and by extension all Views)
* The `keys` keybinding "plugin" (builtin)
* utility methods like `log()`

It does NOT include:
* `events` fifo buffer

## Actions
Actions are functions or `__call`-able tables which must be registered in
`ele.Actions` and must have signature:

```
function action([self,] data, ev, evsend)
```

The action body is free to mutate both `data` and `ev` as well as call
`evsend(newEvent)`. It is also free to call `ctx.schedule(...)` to
schedule coroutines which themselves call `evsend(newEvent)` asynchronously
in order ot update the main loop.

Any events scheduled directly by the action will be handled immediately (the LAP
executor will not be run). The actual implementation of `model()` is:

```
function Ele:model()
  local ev = self.events:pop()
  while ev do
    Actions[ev.action or 'noaction'](self.data, ev, self.events)
    ev = self.events:pop()
  end
end
```

The actual implementation of `intent()` is basically a specialized LAP executor
that calls `model()` when any `events` are present.

## Event Records
Event records MUST be POD (plain old data). This is asserted on by
`evsend()`.

Events are a table with some fields defined, mainly:
 * action: the action name that should be executed. This must be
   registered in `ele.Actions`. See **Action** section above.
 * cause: (debugging only) a list of keys/etc that led to this action.
 * other data: used by the action function (this object is its second argument)

## Plugin Architecture
It is extremely simple to add plugins:

* register relevant `Actions` fields for your plugin. When an event with
  `action` is emitted then that action will be called by `model()`.
* (optional) initialize your plugin in `data`
* (optional) for listening to editor changes register with `ele.changes`, i.e.
  `push(ele.changes.fileOpened, myPluginFunction)`. It will be called like it
  is an action for such events.
* (optional) for listening to real events, schedule your plugin using
  `ctx.schedule(...)` (i.e. the builtin `Keys` plugin does this).

## Keys Builtin Plugin {#keys}
Keys is a builtin plugin which handles actions associated with modal or chorded
(aka vim or emacs style) keyboard input sequences. Users assign keybinding
functions to `Data.bindings` and add binding chains (nested tables) to one of
the `Data.bindings.modes` tables.

Keybinding functions receive `Data.keys`  as their ONLY argument . `keys` POD,
see ele/keys.lua for the fields.

The basic operation is that the `keyinput` action walks the bindings in the
mode, updating `Data.keys.next` until it gets to an action to perform. It then
calls the binding function, scheduling an event if one is returned.

The binding functions can directly mutate Keys, or they can emit an event which
calls an action to mutate data or schedule coroutines. Core data is never
modified by the keybinding itself, which makes logging (and replaying) user
actions trivial (see `Data.bindings.listen`) which permits recording macros/etc.

The event can have the following special fields:
* `mode`: if set then `keys.mode` is set to this after the event is emitted.
  Makes `change`-like commands much simpler.
