import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL as string|undefined;
const key=import.meta.env.VITE_SUPABASE_ANON_KEY as string|undefined;
export const configured=!!url&&!!key;
const storage={getItem:(k:string)=>sessionStorage.getItem(k),setItem:(k:string,v:string)=>sessionStorage.setItem(k,v),removeItem:(k:string)=>sessionStorage.removeItem(k)};
export const db=createClient(url||'https://placeholder.supabase.co',key||'placeholder',{auth:{storage,persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
export type Identity={id:string;public_code:string;expires_at:string};
export type Conversation={id:string;created_at:string;expires_at:string;status:'pending'|'accepted';initiator_id:string;recipient_id:string;other_code:string;last_message?:string;unread?:number};
export type Message={id:string;conversation_id:string;sender_id:string;content:string|null;created_at:string;attachment_path:string|null;attachment_name:string|null;attachment_size:number|null;client_id:string|null};
export function explain(error:unknown){return error instanceof Error?error.message:String(error)}
