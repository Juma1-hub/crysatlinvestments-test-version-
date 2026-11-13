"use client";
import {useEffect,useState} from "react";
import {getSupabaseBrowserClient} from "@/lib/supabase";
export function CurrencyValue({amount=0,sourceCurrency="KES"}:{amount?:number;sourceCurrency?:string}){
 const [currency,setCurrency]=useState("KES"),[rate,setRate]=useState<number|null>(1),[ready,setReady]=useState(false);
 useEffect(()=>{let live=true;const db=getSupabaseBrowserClient();if(!db)return;const load=async()=>{const {data:{user}}=await db.auth.getUser();if(!user)return;const {data}=await db.from("investor_profiles").select("preferred_currency").eq("id",user.id).maybeSingle();if(live&&data?.preferred_currency)setCurrency(data.preferred_currency);};void load();const onChange=(event:Event)=>{const value=(event as CustomEvent<string>).detail;if(value)setCurrency(value)};window.addEventListener("crystal-currency-change",onChange);return()=>{live=false;window.removeEventListener("crystal-currency-change",onChange)}},[]);
 useEffect(()=>{let live=true;setReady(false);if(sourceCurrency===currency){setRate(1);setReady(true);return;}const db=getSupabaseBrowserClient();if(!db){setRate(null);setReady(true);return;}void db.from("crystal_fx_rates").select("rate").eq("base_currency",sourceCurrency).eq("quote_currency",currency).maybeSingle().then(({data,error})=>{if(!live)return;setRate(!error&&data?Number(data.rate):null);setReady(true)});return()=>{live=false}},[sourceCurrency,currency]);
 const converted=sourceCurrency===currency?amount:rate===null?null:amount*rate;
 return <span title={converted===null?"Exchange rate unavailable":"Converted using the exchange rate stored in the account system"}>{!ready||converted===null?"Rates unavailable":`${currency} ${converted.toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2})}`}</span>;
}
