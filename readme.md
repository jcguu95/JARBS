Run the following command *right after* a clean installation of arch linux.

```
sh ./main.sh
```

### TODOs

+ [ ] Break installation into phases. Inform user what the script is going to
  do next, and ask for permission before proceeding.
+ [ ] Figure out why `putgitrepo` asks for password two times.
+ [ ] Make it clear that we want to be independent to arch's haskell libraries.
  That is, in particular, we're not going to download xmonad and xmobar from
  arch repo.
+ [ ] Using stow for config. `linker.sh` is deprecated.
