import { NextRequest, NextResponse } from "next/server";

/**
 * Publication gate and transport hardening.
 * Authentication/authorization remains enforced by Supabase Auth + database RLS/RPC,
 * never by trusting a user ID supplied by the browser.
 */
export function middleware(request: NextRequest) {
  // Never serve production requests over plain HTTP.
  if (process.env.NODE_ENV === "production" && request.nextUrl.protocol === "http:") {
    const secureUrl = request.nextUrl.clone();
    secureUrl.protocol = "https:";
    return NextResponse.redirect(secureUrl, 308);
  }

  if (process.env.CRYSTAL_SITE_PUBLISHED !== "true") {
    const path = request.nextUrl.pathname;
    const allowedPrivateRoutes = ["/admin", "/forgot-password", "/reset-password"];
    const isPrivateSetupRoute = allowedPrivateRoutes.some(route => path === route || path.startsWith(`${route}/`));
    const isFrameworkAsset = path.startsWith("/_next/") || path.startsWith("/api/");
    const isStaticAsset = path === "/manifest.webmanifest" || /\.(?:avif|css|gif|ico|jpeg|jpg|js|json|png|svg|txt|webp|woff2?)$/i.test(path);

    if (!isPrivateSetupRoute && !isFrameworkAsset && !isStaticAsset) {
      return new NextResponse(null, { status: 404 });
    }
  }

  const response = NextResponse.next();
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  if (process.env.NODE_ENV === "production") {
    response.headers.set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload");
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image).*)"],
};
