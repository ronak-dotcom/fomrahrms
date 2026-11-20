# Running checks locally

GitHub Actions has been removed (billing), so **nothing runs these
automatically any more**. Run them yourself before pushing:

```bash
flutter pub get
flutter analyze          # static analysis
flutter test             # unit tests
flutter build web --release --no-tree-shake-icons
```

## Why this matters more than it used to

The test suite in `test/` pins behaviour that decides real numbers —
permission minutes, earned-leave accrual, the 26th-to-25th attendance cycle,
and the payroll maths. Several of those tests are *characterisation* tests:
they assert current behaviour **including known bugs**, each marked `BUG` in a
comment. They are meant to fail when the bug is fixed, so the expectation is
updated in the same commit as the fix.

`flutter test` now runs on every Vercel deploy and **blocks** it on failure,
so a broken test stops the push from going live. Run it locally first anyway;
a failed deploy is slower to find than a failed local run. If you change
anything in `lib/models/leave_store.dart`, `lib/utils/attendance_cycle.dart`,
`lib/utils/el_accrual.dart` or `lib/models/payslip_store.dart`, run
`flutter test` before you push.

## Deployment

- **Vercel** builds and deploys the web app automatically on push to `main`
  (see `vercel-build.sh`). This is unaffected by the removal of Actions.
- **GitHub Pages** was published by the deleted workflow and will now go
  stale. Vercel is the live deployment.
- **Supabase Edge Functions** and **migrations** are deployed separately and
  were never part of the workflow.

## Money rules in the database

Payroll, leave balance, late LOP and permission LOP are worked out in SQL
(`generate_payroll`, `leave_balance`, `late_lop_days`, `permission_lop_days`
and the leave triggers). Their tests live in the database too:

```sql
select * from run_money_rule_tests() where not passed;
```

An empty result means every rule still gives the expected figure. Run it
after any change to those functions. It builds made-up employees in a 2030
cycle and rolls everything back, so it is safe on the live project. The
nightly consistency check (`run_integrity_checks`, 01:30 IST) runs it too and
shows any failure on Management's App Health page.
