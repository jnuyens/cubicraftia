-- Migration 003: Profiles table
-- Stores display names for builders. username must be unique across all accounts.
-- Any authenticated user can read profiles (needed for friend search by username).
-- Users may only update their own profile row.

CREATE TABLE public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT NOT NULL UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read profiles (for friend search)
CREATE POLICY "Authenticated users read profiles"
  ON public.profiles FOR SELECT
  TO authenticated
  USING ( TRUE );

-- Users create their own profile row.
-- CR-10: Without this INSERT policy RLS blocks all inserts — no user can ever
-- create their profile, breaking the display-name system entirely.
CREATE POLICY "Users create own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = id );

-- Users update only their own profile
CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING ( (SELECT auth.uid()) = id )
  WITH CHECK ( (SELECT auth.uid()) = id );
