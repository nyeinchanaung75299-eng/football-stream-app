import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createTelegramHandler } from "../_shared/nca_telegram_bot.mjs";

const handler = createTelegramHandler({
  mode: "viewer",
  env: Deno.env.toObject(),
});

Deno.serve(handler);
