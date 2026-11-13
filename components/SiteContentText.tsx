"use client";
import {useEffect,useState} from "react";
import {getSupabaseBrowserClient} from "@/lib/supabase";
export default function SiteContentText({field,fallback}:{field:string;fallback:string}){
 const [value,setValue]=useState(fallback);
 useEffect(()=>{let live=true;const sync=async()=>{const db=getSupabaseBrowserClient();if(!db){setValue(fallback);return;}const {data,error}=await db.rpc("get_crystal_site_configuration",{p_key:"website_content"});if(!live)return;const candidate=data?.[field];setValue(!error&&typeof candidate==="string"&&candidate.trim()?candidate:fallback);};void sync();window.addEventListener("crystal-site-configuration-change",sync);return()=>{live=false;window.removeEventListener("crystal-site-configuration-change",sync)}},[field,fallback]);
 return <>{value}</>;
}
