import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createMonitor } from "./core.mjs";

// Authentication and the current database Admin role are checked in core.mjs
// before privileged queries or provider keys are used.
Deno.serve(createMonitor(Deno.env.toObject()));
