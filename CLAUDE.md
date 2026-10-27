# DSD Atlas: project management tool

Context for Claude Code. This file summarises how the tool is built, the decisions behind it and how Carlota likes to work, so a new session can pick up without re-explaining. Last updated: 20 October 2026.

## Who and what

- **Owner and sole admin:** Carlota (csolla@digitalsmiledesign.com), project manager at Digital Smile Design (DSD), Madrid HQ. She does not lead the Marketing team: she manages its resources (70/30 split), filters and prioritises requests, and connects it with stakeholders.
- **DSD:** a dental-industry company (cosmetic and restorative dentistry, treatment planning, dentist education), founded by Christian Coachman. About 68 staff.
- **The tool:** **DSD Atlas** (named 22 October 2026; the repo and URL still say `dsd-projects`), a custom project management app replacing Asana for all DSD staff. One URL, individual logins, live updates for everyone.
- **Marketing team:** Marita, Daisy, Steph, Carlota. Their profile names in Supabase were created from email usernames (`mmacdona…`, `dmason…`, `swrennall…`). Match people by **email**, never by name.

## Stack and deployment

- **Frontend:** a single file, `index.html` (HTML, CSS and vanilla JS in one IIFE), in the repo `csolla/dsd-projects`, served by GitHub Pages at https://csolla.github.io/dsd-projects/
- **Backend:** Supabase (`https://yxevnyyzezfdsbclhvvp.supabase.co`), with Row Level Security on and Realtime subscriptions. The client is loaded from the jsDelivr CDN (`@supabase/supabase-js@2`).
- **Auth:** magic link by email, with no passwords. Only `@digitalsmiledesign.com` emails can create an account (migration 12, plus a check on the login screen), and they become `role = 'staff'`. The app still has a "staff only" screen for any non-staff profile, but none existed when sign-ups were locked.
- **Deploying:** commit and push from Claude Code, then Carlota does a hard refresh (Cmd+Shift+R). Carlota sometimes also edits `index.html` through GitHub's web editor with help from another Claude chat, so **always `git pull` before starting any change**.
- **SQL:** migrations are run by hand in the Supabase SQL editor, each as a new query. When giving Carlota SQL, give only the code block. She once pasted a whole explanation into the editor by mistake. Copying long SQL from the Claude Code terminal can drop text, so write it to a file in `supabase/migrations/`, put it on her clipboard with `pbcopy`, and have her paste it with Cmd+A then Cmd+V.
- **Security checks:** the Supabase "public" (anon) key in `index.html` is meant to be public. Access is enforced by Row Level Security. To test what an anonymous visitor sees, query `/rest/v1/<table>` with only that key, and count rows rather than printing data.
- **Claude Artifacts can't call Supabase.** Their content-security policy blocks it, so the tool must stay externally hosted.

## SQL migrations, in order

Earlier ones: base schema, subtasks enrichment, budget, attachments and dependencies. Then:

1. `05_resourcing.sql` adds:
   - profile columns `is_admin`, `resourcing_bu` (the director's unit) and `counts_in_capacity`
   - project columns `business_unit`, `planned_hours`, `priority`, `is_unplanned`, `unplanned_status`, `requested_on` and `swapped_for`
   - the table `time_entries`, plus the `resourcing_totals(start, end)` function (security definer)
   - the tables `resourcing_meetings`, `resourcing_items` (decisions and actions) and `resourcing_flags` (flags for Brendon, admin only)
   - helper functions `is_resourcing_admin()`, `my_resourcing_bu()` and `bu_rollup()`
   - a trigger that stops non-admins from changing the resourcing columns (it didn't cover `role` until migration 10)
2. `06_capacity_limits.sql` adds:
   - profile columns `daily_hours` and `holiday_region` ('Madrid' or 'England')
   - the tables `public_holidays` and `time_off`
   - the functions `resourcing_month_capacity_raw(month)` (internal) and `resourcing_month_capacity(month)` (admin and directors only)
   - the table `resourcing_alerts`, and the trigger `check_resourcing_limits` on `time_entries`, which notifies the admin at 80% and 100% of a unit's limit
   - notification columns `message` and `business_unit`, with the check on `type` dropped
   - an admin update policy on `profiles`
3. `07_work_requests.sql` adds the project columns `requested_by`, `request_details`, `request_deadline` and `request_urgent`, and a trigger `notify_work_request` that notifies the admin when a director requests work.
4. `08_shared_campaigns.sql` adds project columns `budget_education` and `budget_pc`, the task column `business_unit`, and the time entry column `split_group` (it links the two halves of a shared entry).
5. `09_unify_business_units.sql` moves Delight into Planning Center everywhere and makes `projects.team` mirror `business_unit`. It restricts the allowed options to Education, Planning Center, Corporate and Shared for projects and tasks, and to Education, Planning Center and Corporate for time entries.
6. `10_lock_role.sql` (security fix, run 20 October 2026):
   - adds `role` to the admin-only columns in the `protect_resourcing_profile_cols` trigger. Before this, the "users update own profile" policy let a client make themselves staff
   - sets `security_invoker` on the `project_progress` view, which was readable without logging in
   - replaces "profiles viewable by signed-in users" with "profiles viewable by staff or self", using the new security definer helper `i_am_staff()`, so outsiders can't see the staff list
7. `11_remove_client_project_access.sql` (run 20 October 2026) drops the "clients view shared projects" policy on `projects`, so clients see no projects at all. `share_with_client` and `project_clients` are kept, so client sharing can be restored by recreating the policy.
8. `12_dsd_emails_only.sql` (run 20 October 2026) makes `handle_new_user()` raise an exception for any email not ending in `@digitalsmiledesign.com`, so the account is never created and no link is sent. To let an outsider in again (a freelancer, say), this function needs changing.
9. `13_operational_column.sql` (run 22 October 2026) adds the task status `operational` (the "Operational" board column). Every project gets a "Meetings" task there (trigger `project_meetings_task` on insert; `project_meetings_task_bu` keeps its business unit in step with the project). `project_progress` ignores operational tasks, and the app leaves them out of overdue, due-this-week, unassigned and workload counts.
10. `14_shared_meetings_tasks.sql` (run 22 October 2026) replaces the Meetings logic with `sync_meetings_tasks(project, bu)`: Shared projects get two Meetings tasks (Education and Planning Center), others one. On a business unit change, unwanted Meetings tasks are reused for a missing unit, or deleted if unused (no comments, subtasks, files or hours).

Migrations 05 onwards are kept in the repo under `supabase/migrations/`. The base schema (01–04) isn't in the repo.

## Business units and departments (unified, October 2026)

- **Business units:** Education, Planning Center and Corporate. Used for projects, tasks, hours, filters and Resourcing. In the code these are `BUSINESS_UNITS` / `BUS`.
- **Shared:** an extra option for projects and tasks, for campaigns that serve both Education and Planning Center (`PROJECT_BUS`). Hours logged as Shared are split **70% Education / 30% Planning Center** when they're saved, as two `time_entries` rows with the same `split_group`. In the interface they show as one entry.
- **Delight** no longer exists. It's folded into Planning Center.
- **Marketing** is only a *people department* (`TEAMS`, for profiles), never a project or hours option.
- **Projects have one field: Business unit.** The Team field was removed from the interface. `projects.team` is kept in sync with the business unit for compatibility.
- **Client projects were removed** from the interface in October 2026, and clients lost database access to them in migration 11. The data is still in the database, and the code could be restored if needed.

## Features (current)

- Kanban board, a task detail panel (subtasks, dependencies, attachments, comments, @mentions), portfolios (create and delete), global search with filters, a dashboard with DSD, Team and Me scopes, a timeline and a team page.
- **My tasks:** every task assigned to you, grouped Overdue, Today, This week, Later and No date. Done tasks are hidden unless you tick the toggle. You can tick a task done or change its status inline, and clicking a row opens the task panel.
- **My time:** each person logs hours by week, against a project, an optional task and a business unit. The unit comes from the task's tag, or from the project unless the project is Shared. Time can also be logged from inside the task panel.
- **Team time** (admin only, at the bottom of My time, `renderTeamTime()`): a Week / Month switch and a person filter ("Everybody" by default). Week mode follows the page's week buttons and shows hours per day (weekend columns only when someone logged weekend time). Month mode has its own ‹ › arrows and shows hours per week of the month. People listed are everyone who has ever logged time plus everyone counted in capacity. Picking one person adds their entries with unit chips below the grid.
- **Resourcing,** visible to the admin and the two directors (simplified 21 October 2026):
  - A month picker at the top drives every figure. The "To-dos" meeting picker only selects which meeting's to-dos appear.
  - **Monthly limit:** used vs limit per unit, with "Within limit", "Warning: over 80%" or "Limit reached". Below the bars: Shared (no bar, already counted 70/30 in the bars) and Corporate (admin only, no limit). Clicking a unit opens the projects its hours went to (`state.resOpenUnits`), top 5 with "Show all" (`state.resShowAll`). Projects come from `state.timeEntries` (capacity people only), named by project, else the entry's label, else "Other / no project"; Education and Planning Center lists end with one "Shared work" line so they add up to the bar.
  - **Month by month:** a bar chart of hours used per month, with dashed lines marking each unit's limit.
  - **Campaigns planned for <month>:** the unit's scheduled campaigns whose dates overlap the month, with planned hours (editable by the admin) and hours this month. Imported hours that aren't linked to a campaign can be linked from here.
  - **Unplanned requests:** requests still waiting for a decision (including ones directors submit through **Request work**). The admin can **Add to pipeline** or **Decline**.
  - **Upcoming pipeline:** scheduled campaigns that start after the selected month.
  - **To-dos:** a simple list per meeting (text plus optional owner), stored in `resourcing_items` with `kind = 'action'`. Open to-dos from earlier meetings carry over. A failed save shows an alert.
  - **Planned workload by person** (admin only, `workloadPanelHtml()` / `plannedWorkload()`, added 27 October 2026): for the selected month, estimated hours of open tasks and subtasks due that month, per assignee, split by business unit (Shared tasks 70/30; subtasks take their parent task's unit and, without a date of their own, its due date). Shown against each person's capacity after the buffer. Tasks with no due date are listed per person; hours assigned to people not counted in capacity are left out. Needs `subtasks` loaded with `task_id` and `due_date` (`loadOpenSubtasks`).
  - **Team capacity** (admin only): the Counted switch, hours per day, holiday calendar, time off, bank holidays and the "Logged so far" check against hours available.
  - **Import workbook hours:** CSV or pasted rows from the old Marketing time log sheet. Duplicates are skipped.
  - Removed in the simplification: "Hours vs allocation" and "Flags for Brendon". The `resourcing_flags` table and `renderFlagsPanel()` still exist but aren't shown.
- **Shared campaign panel** on a Shared project's board (admin and directors): budget, own tasks, share of shared work, total and balance per unit, plus a check on what percentage of hours are shared, flagged above 30%.
- **Light / dark mode:** a moon/sun button in the top-right corner of every page. The choice is saved in that browser (`localStorage` key `dsd-theme`) and applied by a small script in `<head>` before the page paints. With no saved choice, the app follows the computer's setting. Colours are CSS variables on `:root`, with dark values under `[data-theme="dark"]` and the system media query. Use `var(--on-accent)` for text on teal or coral fills, never `#fff`.
- **Notifications:** assignments, mentions, limit alerts and work requests. Clicking a limit alert or a request opens Resourcing.

## Resourcing rules

- **Directors:** Education is Carlos (`resourcing_bu = 'Education'`). Planning Center's director is John Coachman, but Carlota meets **JJ** (in Miami), who has `resourcing_bu = 'Planning Center'`. Each sees only their own unit's numbers.
- **Meetings, from a resourcing view only:**
  - Carlos: every other Thursday at 13:00, in person, starting 22 October 2026.
  - JJ: every 4 weeks on Google Meet at 16:00 Madrid / 10:00 Miami, in the same week as a Carlos meeting, starting 22 October 2026.
  - The schedule is set in `MEETING_SERIES` in the code. The 31 December Education slot needs moving.
  - Flags go to Brendon in a separate session.
- **Allocation:** Education gets 70% and Planning Center 30% of **total** Marketing capacity. Corporate has no limit and simply eats into the time available. Only people marked `counts_in_capacity` count, which means Marita, Daisy and Steph, not Carlota.
- **Capacity:** each person's daily hours × working days, minus bank holidays and time off, then minus a **20% buffer** (`CAPACITY_BUFFER = 0.8`, which must match the SQL function).
  - Marita and Daisy: 7.5 hours a day, Madrid calendar.
  - Steph: 6 hours a day, England calendar. She's based in Liverpool.
  - Bank holidays are loaded up to December 2026, plus January to March 2027 (file `supabase/data/2027-q1_bank_holidays.sql`). **The rest of 2027 still needs adding.**
- **Reference figures, capacity after the buffer:** October 2026 is 351.6h (Education 246.1h, Planning Center 105.5h). November is 328.8h (230.2h and 98.6h). December is 283.2h (198.2h and 85.0h), which includes time off for Daisy (28–31 December) and Steph (21–24 and 29–31 December).
- **Alerts:** a warning at 80% of a limit and "limit reached" at 100%. Carlos and JJ see the status, but only Carlota gets notified.
- **Unplanned requests:** logged and reviewed at the next meeting. An urgent one goes in only if something else is dropped, and that swap is recorded.
- **Months you can pick in Resourcing:** from October 2026 to five months ahead of today (`limitMonths()`), so a whole quarter ahead can be planned. Changed from two months ahead on 27 October 2026.
- **Reviewing month by month:** the calendar month is the unit for every figure.
- **Shared campaigns (the method for every campaign that serves both units):**
  - Use one project, marked Shared, with a budget per unit agreed with each director.
  - Tag tasks as Education, Planning Center or Shared. Both the team and Carlota can tag.
  - Shared work is split 70/30, and it counts against the monthly limits like any other work.
  - **Black Friday 2026:** Education budget 190h, Planning Center 80h. That's 40% of capacity from 1 October to 30 November.

## Other context

- **Monthly Marketing catch-up:** Marita, Daisy, Steph and Carlota, for 45 minutes. October's was on 15 October and November's is on **11 November**. The notes are kept in a Claude Doc called "Marketing Catch-ups". October's actions were added to the "Marketing catch-up actions" project, tagged Corporate.
- **Integrations still to build:** Growth Hub, Craft, Google Drive, Google Meet and Google Calendar.

## Open items and ideas

- **Freeze meeting numbers:** a "Close meeting" button that saves a snapshot of the month's figures, so late edits don't change what was discussed. This was proposed and is not built yet.
- Projects left without a business unit after migration 09 need tagging.
- Move the 31 December Education meeting, and add the 2027 bank holidays.
- If someone leaves the team: set their hours a day to 0 rather than unticking Counted. Unticking removes their hours from past months as well.

## How Carlota likes to work

- **Align on parameters and direction before building or drafting.** Ask short, focused questions first.
- She works iteratively: she uses the tool, spots gaps and asks for targeted fixes. Keep changes practical, not complex.
- Explain in plain language what she'll **see** after a change, and give step-by-step deploy instructions.
- When debugging, ask for a screenshot of the result. Common causes so far:
  - The page wasn't redeployed, or needed a hard refresh.
  - A SQL update matched people by name, and the names didn't match.

## Testing approach used so far

Changes were checked by syntax-checking the extracted script with `node --check`, then loading the page in headless Chromium (Playwright) with a mock `window.supabase`. The mock is an in-memory query builder plus stubbed `rpc`, `channel` and `auth`, seeded with test data. Each change was exercised as the admin (Carlota), as a director (Carlos) and as a team member (Daisy).
