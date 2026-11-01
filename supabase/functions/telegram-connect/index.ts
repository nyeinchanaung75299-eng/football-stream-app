import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createTelegramConnect } from "../_shared/telegram_connect.mjs";

Deno.serve(createTelegramConnect(Deno.env.toObject()));
