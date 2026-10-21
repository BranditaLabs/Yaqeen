import { NextResponse, type NextRequest } from 'next/server';
import { SESSION_COOKIE } from './lib/session';

/** Cheap gate: no cookie → login. The API still validates the token on every call. */
export function middleware(req: NextRequest) {
  const hasSession = req.cookies.has(SESSION_COOKIE);
  const isLogin = req.nextUrl.pathname.startsWith('/login');
  if (!hasSession && !isLogin) return NextResponse.redirect(new URL('/login', req.url));
  if (hasSession && isLogin) return NextResponse.redirect(new URL('/', req.url));
  return NextResponse.next();
}

export const config = { matcher: ['/((?!_next|favicon.ico|.*\\.(?:png|svg|ico)$).*)'] };
