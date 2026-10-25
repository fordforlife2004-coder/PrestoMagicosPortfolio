# Hello

The first script in my portfolio: `/hello` greets you by name in chat and as a notification.

v2 fix: in v1 the command's code was pasted inside `fxmanifest.lua` and the `client.lua` the manifest pointed to didn't exist, so the resource failed to start. The code now lives in [`client.lua`](client.lua) and the manifest only describes the resource.

```cfg
ensure scriptname
```
