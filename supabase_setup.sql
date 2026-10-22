-- Run in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;
create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  normalized_name text not null unique,
  status text not null default 'started' check (status in ('started','finished')),
  score integer,
  total integer not null default 20,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint score_range check (score is null or (score >= 0 and score <= total))
);
create table if not exists public.quiz_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.quiz_attempts enable row level security;
alter table public.quiz_admins enable row level security;
revoke all on public.quiz_attempts from anon, authenticated;
grant select on public.quiz_attempts to authenticated;
grant select on public.quiz_admins to authenticated;
create or replace function public.reserve_quiz_attempt(p_full_name text, p_normalized_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if length(trim(p_full_name)) < 5 or array_length(regexp_split_to_array(trim(p_full_name), '\s+'),1) < 3 then raise exception 'full_name_required'; end if;
  insert into public.quiz_attempts(full_name, normalized_name) values (trim(p_full_name), lower(trim(regexp_replace(p_normalized_name, '\s+', ' ', 'g')))) returning id into new_id;
  return new_id;
exception when unique_violation then raise exception 'already_taken';
end; $$;
create or replace function public.finish_quiz_attempt(p_attempt_id uuid, p_score integer, p_total integer)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_total <> 20 or p_score < 0 or p_score > p_total then raise exception 'invalid_score'; end if;
  update public.quiz_attempts set status='finished', score=p_score, total=p_total, finished_at=now()
    where id=p_attempt_id and status='started';
  return found;
end; $$;
drop policy if exists "admins read attempts" on public.quiz_attempts;
create policy "admins read attempts" on public.quiz_attempts for select to authenticated
using (exists (select 1 from public.quiz_admins a where a.user_id = auth.uid()));
drop policy if exists "admins read admins" on public.quiz_admins;
create policy "admins read admins" on public.quiz_admins for select to authenticated
using (user_id = auth.uid());

-- Grant execution only after both functions have been created.
grant execute on function public.reserve_quiz_attempt(text,text) to anon, authenticated;
grant execute on function public.finish_quiz_attempt(uuid,integer,integer) to anon, authenticated;
