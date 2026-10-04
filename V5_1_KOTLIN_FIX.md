# V5.1 Kotlin build fix

Fixes the Android Viewer Kotlin compilation failure.

The Media3 media source factory was previously constructed with:

`DefaultMediaSourceFactory(this, httpFactory)`

That overload expects an `ExtractorsFactory` as its second argument, not a
`DataSource.Factory`. V5.1 now uses:

`DefaultMediaSourceFactory(httpFactory)`

The native player activity is also explicitly annotated with `@UnstableApi`
for the Media3 APIs used by the custom DRM/media-source setup.
