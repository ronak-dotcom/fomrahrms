# October 2026 reconciliation against the approved salary sheets (10 Nov 2026)

Schema and rule changes applied to the live database on this date. The exact
definitions are in the database (pg_get_functiondef); this file records what
changed and why, so the repository does not fall behind again.

- generate_payroll: total_deductions and net_pay now include the flat monthly
  PF, ESI and TDS from salary_structures. Previously only professional tax
  was subtracted. LOP days are read exactly from leave_applications.
- leave_applications.lop_days is numeric(5,1); lop_days_override and the
  set_leave_lop_split() RPC let HR or Management record the agreed split.
- leave_balance: counts paid days only (days - lop_days) and ignores comp off.
- enforce_probation_leave_rules: a comp off is not the probationer's one
  leave per cycle.
- late_lop_decisions.lop_days_override: the settled late LOP for a cycle;
  late_lop_days() returns it in place of the rule's figure.
- salary_structures: Fomra Developers component splits, exact PF for
  FHIPL-20 and FHIPL-25, and structures for the three exits, all taken from
  the October 2026 master sheets.

Data recorded for the 26 Sep - 25 Oct cycle, per the sheets and Management:
comp offs for working 2 October (FHIPL-03, -24, -25, -26), leave for
FHIPL-03 (23 Oct, ML) and FHIPL-24 (21 Oct, CL), Saurabh Chandak's leave as
1.5 CL + 2.5 LOP, Yuvaraj S's EL with no LOP, and late LOP of 0.5 day
(FD-04) and 1.5 days (FD-05).

Result: generate_payroll('2026-10-25') equals the sheets' net pay for all
twelve active employees.
