// Deploy with `supabase functions deploy cleanup --no-verify-jwt`.
// Schedule via Supabase Cron/pg_net and authenticate with CLEANUP_SECRET.
import {createClient} from 'npm:@supabase/supabase-js@2';
Deno.serve(async req=>{
 if(req.method!=='POST'||!Deno.env.get('CLEANUP_SECRET')||req.headers.get('x-cleanup-secret')!==Deno.env.get('CLEANUP_SECRET'))return new Response('Unauthorized',{status:401});
 const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const db=createClient(url,key,{auth:{persistSession:false}});
 const now=new Date().toISOString();
 const {data:expired,error}=await db.from('conversations').select('id').lte('expires_at',now).limit(500);
 if(error)return new Response(error.message,{status:500});
 let removed=0;
 for(const conversation of expired||[]){
  const {data:files,error:listError}=await db.storage.from('attachments').list(conversation.id,{limit:1000});
  if(listError)return new Response(listError.message,{status:500});
  // Files live at conversationId/userId/fileId; list recursively by user folders.
  for(const folder of files||[]){
   const {data:objects,error:innerError}=await db.storage.from('attachments').list(`${conversation.id}/${folder.name}`,{limit:1000});
   if(innerError)return new Response(innerError.message,{status:500});
   const paths=(objects||[]).map(o=>`${conversation.id}/${folder.name}/${o.name}`);
   if(paths.length){const {error:deleteError}=await db.storage.from('attachments').remove(paths);if(deleteError)return new Response(deleteError.message,{status:500})}
  }
  const {error:delError}=await db.from('conversations').delete().eq('id',conversation.id);
  if(delError)return new Response(delError.message,{status:500});removed++;
 }
 const {data:expiredIds}=await db.from('identities').select('id').lte('expires_at',now).limit(500);
 for(const row of expiredIds||[]){
  const {data:membership}=await db.from('conversations').select('id').or(`initiator_id.eq.${row.id},recipient_id.eq.${row.id}`).limit(1);
  if(!membership?.length){await db.from('identities').delete().eq('id',row.id);await db.auth.admin.deleteUser(row.id)}
 }
 return Response.json({removedConversations:removed});
});
