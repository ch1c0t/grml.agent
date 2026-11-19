# Source layout

The source tree uses BGEM's `pre.<Module>` directories to make mixin
composition inspectable. Public entry points live below `pre.Public/`;
private helpers live below `pre.Private/`. Each method has its own
PascalCase source file. For example:

```sh
tree src.source/GRML/pre.Agent/pre.Storage src.source/GRML/pre.Agent/pre.PrepareBuildEnvironment src.source/GRML/pre.Agent/pre.BuildISO
```

The `Public.cr` and `Private.cr` files list the modules included by the
containing component. Nested `pre.<Component>` directories group the method
modules that belong to that component; opening those files shows the exact
calls between methods.

## Source of truth and build

`src.source/` is the authoritative source tree. BGEM generates the
`src/` Crystal entry point and assembled module files from that tree; edit
the `src.source/` files rather than hand-editing generated files.

The repository's default Rake task runs BGEM source generation and then
builds the Crystal application:

```sh
bundle install
shards install
bundle exec rake
```

The build step is equivalent to running `bundle exec bgem` followed by
`shards build`. The generated application entry point is under `src/`;
the application target is `grml.agent`.
