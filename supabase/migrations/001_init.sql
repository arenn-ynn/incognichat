-- Apply once in Supabase SQL Editor. Enable anonymous sign-ins in Auth settings first.
create extension if not exists pgcrypto;
create table public.identities (
 id uuid primary key references auth.users(id) on delete cascade,
 public_code text not null unique check (public_code ~ '^[A-Z0-9]{6}$'),
 created_at timestamptz not null default now(),
 last_active_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '24 hours')
);
create table public.conversations (
 id uuid primary key default gen_random_uuid(),
 initiator_id uuid not null references public.identities(id),
 recipient_id uuid not null references public.identities(id),
 status text not null default 'pending' check(status in ('pending','accepted')),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default(now()+interval '24 hours'),
 check(initiator_id <> recipient_id)
);
create table public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references public.identities(id),
 content text check(char_length(content)<=10000),
 attachment_path text,
 attachment_name text,
 attachment_size bigint check(attachment_size>=0 and attachment_size<=10485760),
 client_id uuid,
 created_at timestamptz not null default now(),
 check(content is not null or attachment_path is not null),
 unique(sender_id,client_id)
);
create index conversations_initiator_idx on public.conversations(initiator_id);
create index conversations_recipient_idx on public.conversations(recipient_id);
create index messages_conversation_idx on public.messages(conversation_id,created_at);
create or replace function public.make_code() returns text language plpgsql as $$
declare alphabet text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; result text:=''; bytes bytea:=gen_random_bytes(6); i int;
begin for i in 0..5 loop result:=result||substr(alphabet,(get_byte(bytes,i)%length(alphabet))+1,1);end loop;return result;end $$;
create or replace function public.ensure_identity() returns public.identities language plpgsql security definer set search_path=public as $$
declare result public.identities; i int;
begin
 if auth.uid() is null or not coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Anonymous authentication required';end if;
 select * into result from identities where id=auth.uid() and expires_at>now();
 if found then update identities set last_active_at=now(),expires_at=now()+interval '24 hours' where id=auth.uid() returning * into result;return result;end if;
 if exists(select 1 from identities where id=auth.uid()) then raise exception 'Identity expired; start a new session';end if;
 for i in 1..20 loop
 begin insert into identities(id,public_code) values(auth.uid(),make_code()) returning * into result;return result;
 exception when unique_violation then null;end;
 end loop;
 raise exception 'Could not allocate a code';
end $$;
create or replace function public.request_conversation(target_code text) returns uuid language plpgsql security definer set search_path=public as $$
declare target uuid; cid uuid;
begin
 if not exists(select 1 from identities where id=auth.uid() and expires_at>now()) then raise exception 'Your session expired';end if;
 select id into target from identities where public_code=upper(trim(target_code)) and expires_at>now();
 if target is null then raise exception 'Code not found or expired';end if;
 if target=auth.uid() then raise exception 'You cannot message yourself';end if;
 select id into cid from conversations where expires_at>now() and ((initiator_id=auth.uid() and recipient_id=target) or (recipient_id=auth.uid() and initiator_id=target)) limit 1;
 if cid is not null then return cid;end if;
 insert into conversations(initiator_id,recipient_id) values(auth.uid(),target) returning id into cid;return cid;
end $$;
create or replace function public.accept_conversation(cid uuid) returns void language plpgsql security definer set search_path=public as $$
begin update conversations set status='accepted' where id=cid and recipient_id=auth.uid() and status='pending' and expires_at>now();if not found then raise exception 'Invitation unavailable';end if;end $$;
create or replace function public.send_message(cid uuid,body text, file_path text default null,file_name text default null,file_size bigint default null,request_id uuid default null) returns uuid language plpgsql security definer set search_path=public as $$
declare mid uuid;
begin
 if not exists(select 1 from conversations where id=cid and status='accepted' and expires_at>now() and auth.uid() in (initiator_id,recipient_id)) then raise exception 'Conversation not accessible';end if;
 if not exists(select 1 from identities where id=auth.uid() and expires_at>now()) then raise exception 'Identity expired';end if;
 if char_length(coalesce(body,''))>10000 then raise exception 'Message too long';end if;
 if (body is null or btrim(body)='') and file_path is null then raise exception 'Empty message';end if;
 if file_path is not null and (file_path not like cid::text||'/'||auth.uid()::text||'/%' or file_size>10485760 or file_size<0 or file_name is null) then raise exception 'Invalid attachment';end if;
 insert into messages(conversation_id,sender_id,content,attachment_path,attachment_name,attachment_size,client_id) values(cid,auth.uid(),nullif(btrim(body),''),file_path,left(file_name,255),file_size,request_id)
 on conflict(sender_id,client_id) do update set sender_id=excluded.sender_id returning id into mid;
 update conversations set expires_at=now()+interval '24 hours' where id=cid;
 return mid;
end $$;
alter table public.identities enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
create policy identity_read on public.identities for select to authenticated using (id=auth.uid() or exists(select 1 from public.conversations c where c.expires_at>now() and (c.initiator_id=auth.uid() or c.recipient_id=auth.uid()) and (c.initiator_id=identities.id or c.recipient_id=identities.id)));
create policy conversation_read on public.conversations for select to authenticated using(expires_at>now() and auth.uid() in (initiator_id,recipient_id));
create policy message_read on public.messages for select to authenticated using(exists(select 1 from public.conversations c where c.id=conversation_id and c.status='accepted' and c.expires_at>now() and auth.uid() in(c.initiator_id,c.recipient_id)));
revoke all on function public.make_code() from public,anon,authenticated;
revoke all on function public.ensure_identity() from public,anon;
revoke all on function public.request_conversation(text) from public,anon;
revoke all on function public.accept_conversation(uuid) from public,anon;
revoke all on function public.send_message(uuid,text,text,text,bigint,uuid) from public,anon;
grant execute on function public.ensure_identity() to authenticated;
grant execute on function public.request_conversation(text) to authenticated;
grant execute on function public.accept_conversation(uuid) to authenticated;
grant execute on function public.send_message(uuid,text,text,text,bigint,uuid) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit) values('attachments','attachments',false,10485760) on conflict(id) do update set public=false,file_size_limit=10485760;
create policy attachment_insert on storage.objects for insert to authenticated with check(bucket_id='attachments' and (storage.foldername(name))[2]=auth.uid()::text and exists(select 1 from public.conversations c where c.id::text=(storage.foldername(name))[1] and c.status='accepted' and c.expires_at>now() and auth.uid() in(c.initiator_id,c.recipient_id)));
create policy attachment_read on storage.objects for select to authenticated using(bucket_id='attachments' and exists(select 1 from public.conversations c where c.id::text=(storage.foldername(name))[1] and c.status='accepted' and c.expires_at>now() and auth.uid() in(c.initiator_id,c.recipient_id)));
-- Cleanup is implemented as a DB function; schedule using pg_cron (below).
create or replace function public.cleanup_expired() returns void language plpgsql security definer set search_path=public,storage as $$
begin
 -- Storage deletion via SQL is not supported: run Edge Function cleanup for objects first.
 delete from public.conversations where expires_at<=now();
 delete from public.identities i where i.expires_at<=now() and not exists(select 1 from public.conversations c where i.id in(c.initiator_id,c.recipient_id));
end $$;
revoke all on function public.cleanup_expired() from public,anon,authenticated;
-- IMPORTANT: do not schedule SQL cleanup until Storage objects are removed by a service-role Edge Function.
