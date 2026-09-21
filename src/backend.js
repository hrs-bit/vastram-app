const URL = import.meta.env.VITE_SUPABASE_URL?.replace(/\/$/,'') || '';
const KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || '';
export const cloudEnabled = Boolean(URL && KEY);
import { createClient } from '@supabase/supabase-js';
export const supabase = cloudEnabled ? createClient(URL,KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}) : null;
async function call(path, options={}){
  if(!cloudEnabled) throw new Error('Cloud backend is not configured');
  const session=(await supabase.auth.getSession()).data.session;
  const bearer=session?.access_token || KEY;
  const r=await fetch(`${URL}/rest/v1/${path}`,{...options,headers:{apikey:KEY,Authorization:`Bearer ${bearer}`,'Content-Type':'application/json',...(options.headers||{})}});
  if(!r.ok){let text=await r.text();try{text=JSON.parse(text)?.message||JSON.parse(text)?.hint||text}catch{};throw new Error(text)} return r.status===204?null:r.json();
}
async function rpc(fn,body={}){return call(`rpc/${fn}`,{method:'POST',body:JSON.stringify(body)})}

export const api={
  signUp:(email,password,fullName)=>supabase.auth.signUp({email,password,options:{data:{full_name:fullName}}}),
  signIn:(email,password)=>supabase.auth.signInWithPassword({email,password}),
  signInWithGoogle:()=>supabase.auth.signInWithOAuth({provider:'google',options:{redirectTo:window.location.origin}}),
  resetPassword:(email)=>supabase.auth.resetPasswordForEmail(email,{redirectTo:`${window.location.origin}/reset-password`}),
  signOut:()=>supabase.auth.signOut(),
  session:()=>supabase.auth.getSession(),
  profile:()=>rpc('my_profile'),
  createShop:(name)=>rpc('create_shop',{p_name:name}),
 listProducts:()=>call('products?select=*&active=eq.true&order=created_at.desc'),
 createOrder:(body)=>rpc('create_order',body),
 customerOrder:(token)=>rpc('customer_order',{p_customer_token:token}),
 claimOrder:(code,agentToken)=>rpc('claim_delivery_order',{p_shop_code:code,p_agent_token:agentToken}),
 setEta:(agentToken,eta,distance,traffic)=>rpc('set_delivery_eta',{p_agent_token:agentToken,p_eta_minutes:eta,p_distance_km:distance,p_traffic:traffic}),
 arrived:(agentToken)=>rpc('mark_delivery_arrived',{p_agent_token:agentToken}),
 verify:(agentToken,otp)=>rpc('verify_handover',{p_agent_token:agentToken,p_otp:otp}),
 finish:(agentToken,decision)=>rpc('finish_tryon',{p_agent_token:agentToken,p_decision:decision}),
 merchantOrders:(shopId)=>rpc('merchant_orders',{p_shop_id:shopId}),
 adminStats:()=>rpc('admin_stats'),
 adminOrders:()=>rpc('admin_orders'),
 updateOrderStatus:(orderId,status)=>rpc('admin_update_order',{p_order_id:orderId,p_status:status})
};
export const demoOrder={id:'VST-1042',shop:'Urban Threads',customer:'Demo Customer',items:['Textured Overshirt'],amount:1299,shopCode:'VST-1042',otp:'5821',distance:2.4,eta:18,customerToken:'cust_demo_5821',status:'ready_for_pickup'};
export function makeToken(prefix='token'){return `${prefix}_${crypto?.randomUUID?.()||`${Date.now()}_${Math.random().toString(36).slice(2)}`}`}
export function saveDemoOrder(o){localStorage.setItem('vastramDemoOrder',JSON.stringify(o));if(o?.customerToken)localStorage.setItem('vastramCustomerToken',o.customerToken)}
export function loadDemoOrder(){try{return JSON.parse(localStorage.getItem('vastramDemoOrder')||'null')}catch{return null}}
