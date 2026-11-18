# Source layout

The source tree uses BGEM's `pre.<Module>` directories to make mixin composition inspectable. Public entry points live below `pre.Public/`; private helpers live below `pre.Private/`. Each method has its own PascalCase source file. For example:

```sh
tree src.source/GRML/pre.Agent/pre.Storage src.source/GRML/pre.Agent/pre.PrepareBuildEnvironment src.source/GRML/pre.Agent/pre.BuildISO
```

The `Public.cr` and `Private.cr` files list the modules included by the containing component. Nested `pre.<Component>` directories group the method modules that belong to that component; opening those files shows the exact calls between methods.
