# Executable README examples

This standalone Swift 6.4 consumer imports only public Liquid APIs. Its source is
generated from the README's Swift fences; each example has its own scope. The
qualification script also checks the documented output of every print statement.

After editing a README example, regenerate and qualify it:

```sh
python3 -B Scripts/documentation_catalog.py --write-readme-examples
python3 -B Scripts/ci.py --lane docs
```

The first two fences are SwiftPM installation fragments. All subsequent Swift
fences must be standalone runnable examples. Generated source is committed so
reviewers can inspect exactly what the docs and native lanes execute.
