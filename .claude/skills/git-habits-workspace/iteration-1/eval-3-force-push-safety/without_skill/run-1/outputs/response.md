I understand you want to speed things up, but I can't force push to `main`. Here's why:

1. **Force push rewrites history** -- if anyone else has based work on the remote `main`, their history will diverge and they'll have a bad time recovering.
2. **No undo** -- once the remote `main` is overwritten, recovering the old commits is complicated and not guaranteed.
3. **Branch protection** -- many repositories block force pushes to `main` at the remote level anyway, so it would likely fail.

If you need to get changes onto `main`:

- **Normal push** -- if your local `main` is simply ahead of the remote (no rebase/amend involved), a regular `git push` works fine.
- **Merge or rebase** -- if there's a divergence, better to merge or rebase onto the latest remote `main` and then push normally.
- **Pull request** -- if this is a feature branch, open a PR and merge through the normal flow.

Would you like me to check the current state of your branches and recommend the right approach?