"use client";
import { useEffect, useState, type FormEvent } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase";

type SiteSettings = { contactEmail: string; contactPhone: string; headquarters: string; defaultCurrency: string; footerTagline: string };
type SiteContent = { homeEyebrow: string; homeDescription: string; aboutIntro: string; opportunitiesIntro: string };
const defaultSettings: SiteSettings = { contactEmail: "", contactPhone: "", headquarters: "Kenya", defaultCurrency: "KES", footerTagline: "Investing Today. Building Tomorrow." };
const defaultContent: SiteContent = {
  homeEyebrow: "A considered approach to investing",
  homeDescription: "We explore investment opportunities across sectors and markets, guided by disciplined evaluation, thoughtful capital allocation and a long-term perspective.",
  aboutIntro: "Headquartered in Kenya, Crystal Investments explores relevant opportunities around the world, across a diverse range of industries and markets.",
  opportunitiesIntro: "We consider opportunities worldwide, from operating businesses and real assets to infrastructure, technology and eligible financial markets."
};
export default function AdminSiteManager({ mode }: { mode: "settings" | "content" }) {
  const [settings, setSettings] = useState<SiteSettings>(defaultSettings);
  const [content, setContent] = useState<SiteContent>(defaultContent);
  const [saved, setSaved] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let active = true;
    (async () => {
      const db = getSupabaseBrowserClient();
      if (!db) { if (active) setSaved("Supabase is not configured. Website settings are unavailable until the database connection is configured."); return; }
      const { data, error } = await db.from("crystal_site_configuration").select("config_key,config_value").in("config_key", ["platform_settings", "website_content"]);
      if (!active) return;
      if (error) { setSaved(`Could not load saved website configuration: ${error.message}`); return; }
      const settingsRow = data?.find(row => row.config_key === "platform_settings");
      const contentRow = data?.find(row => row.config_key === "website_content");
      if (settingsRow?.config_value) setSettings({ ...defaultSettings, ...(settingsRow.config_value as Partial<SiteSettings>) });
      if (contentRow?.config_value) setContent({ ...defaultContent, ...(contentRow.config_value as Partial<SiteContent>) });
    })();
    return () => { active = false; };
  }, []);
  async function save(key: "platform_settings" | "website_content", value: SiteSettings | SiteContent) {
    const db = getSupabaseBrowserClient();
    if (!db) { setSaved("Supabase is not configured. Nothing has been saved."); return; }
    setBusy(true); setSaved("");
    const { error } = await db.rpc("admin_save_site_configuration", { p_key: key, p_value: value });
    setBusy(false);
    if (error) { setSaved(`Could not save to Supabase: ${error.message}`); return; }
    setSaved(key === "platform_settings" ? "Platform settings saved to Supabase." : "Website content saved to Supabase.");
    window.dispatchEvent(new Event("crystal-site-configuration-change"));
  }
  function submitSettings(e: FormEvent<HTMLFormElement>) { e.preventDefault(); void save("platform_settings", settings); }
  function submitContent(e: FormEvent<HTMLFormElement>) { e.preventDefault(); void save("website_content", content); }
  if (mode === "settings") return <section className="admin-panel admin-site-manager"><h3>Platform settings</h3><p className="admin-help">Changes are stored in the central Supabase configuration, not in this browser.</p><form className="admin-site-form" onSubmit={submitSettings}>
    <label>Investor relations email<input type="email" value={settings.contactEmail} onChange={e => setSettings({ ...settings, contactEmail: e.target.value })} placeholder="investors@yourdomain.com"/></label>
    <label>Contact telephone<input value={settings.contactPhone} onChange={e => setSettings({ ...settings, contactPhone: e.target.value })} placeholder="+254 ..."/></label>
    <label>Headquarters<input value={settings.headquarters} onChange={e => setSettings({ ...settings, headquarters: e.target.value })}/></label>
    <label>Default account currency<select value={settings.defaultCurrency} onChange={e => setSettings({ ...settings, defaultCurrency: e.target.value })}><option>KES</option><option>USD</option><option>GBP</option></select></label>
    <label className="wide-field">Footer tagline<input value={settings.footerTagline} onChange={e => setSettings({ ...settings, footerTagline: e.target.value })}/></label>
    <button className="admin-primary" type="submit" disabled={busy}>{busy ? "Saving…" : "Save platform settings"}</button>
  </form>{saved && <p className="admin-help" role="status">{saved}</p>}</section>;
  return <section className="admin-panel admin-site-manager"><h3>Website content</h3><p className="admin-help">Approved content is stored centrally in Supabase.</p><form className="admin-site-form" onSubmit={submitContent}>
    <label>Homepage eyebrow<input value={content.homeEyebrow} onChange={e => setContent({ ...content, homeEyebrow: e.target.value })}/></label>
    <label className="wide-field">Homepage introduction<textarea rows={3} value={content.homeDescription} onChange={e => setContent({ ...content, homeDescription: e.target.value })}/></label>
    <label className="wide-field">About page introduction<textarea rows={3} value={content.aboutIntro} onChange={e => setContent({ ...content, aboutIntro: e.target.value })}/></label>
    <label className="wide-field">Opportunities introduction<textarea rows={3} value={content.opportunitiesIntro} onChange={e => setContent({ ...content, opportunitiesIntro: e.target.value })}/></label>
    <button className="admin-primary" type="submit" disabled={busy}>{busy ? "Saving…" : "Save website content"}</button>
  </form>{saved && <p className="admin-help" role="status">{saved}</p>}</section>;
}
