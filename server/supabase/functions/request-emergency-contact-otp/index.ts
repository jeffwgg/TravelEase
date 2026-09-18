import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

async function hashOtp(
  contactId: string,
  code: string,
) {
  const pepper = Deno.env.get("OTP_PEPPER");

  if (!pepper) {
    throw new Error("OTP service is not configured");
  }

  const input = new TextEncoder().encode(
    `${contactId}:${code}:${pepper}`,
  );

  const digest = await crypto.subtle.digest(
    "SHA-256",
    input,
  );

  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function clientsForRequest(request: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get(
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  const authorization =
    request.headers.get("Authorization");

  if (
    !url ||
    !anonKey ||
    !serviceKey ||
    !authorization
  ) {
    throw new Error("Unauthorized");
  }

  const userClient = createClient(url, anonKey, {
    global: {
      headers: {
        Authorization: authorization,
      },
    },
    auth: {
      persistSession: false,
    },
  });

  const { data, error } =
    await userClient.auth.getUser();

  if (error || !data.user) {
    throw new Error("Unauthorized");
  }

  return {
    user: data.user,
    admin: createClient(url, serviceKey, {
      auth: {
        persistSession: false,
      },
    }),
  };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (request.method !== "POST") {
    return jsonResponse(
      { error: "Method not allowed" },
      405,
    );
  }

  try {
    const { user, admin } =
      await clientsForRequest(request);

    const {
      contact_id: contactId,
    } = await request.json();

    if (typeof contactId !== "string") {
      return jsonResponse(
        { error: "A contact ID is required." },
        400,
      );
    }

    const {
      data: contact,
      error: contactError,
    } = await admin
      .from("emergency_contacts")
      .select("id, email, is_verified")
      .eq("id", contactId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (contactError) {
      throw contactError;
    }

    if (!contact) {
      return jsonResponse(
        { error: "Emergency contact not found." },
        404,
      );
    }

    if (contact.is_verified) {
      return jsonResponse(
        { error: "This contact is already verified." },
        409,
      );
    }

    if (!contact.email) {
      return jsonResponse(
        {
          error:
            "Add an email address before verification.",
        },
        400,
      );
    }

    const {
      data: existing,
    } = await admin
      .from("emergency_contact_verifications")
      .select("last_sent_at")
      .eq("contact_id", contactId)
      .maybeSingle();

    if (existing?.last_sent_at) {
      const elapsed =
        Date.now() -
        new Date(existing.last_sent_at).getTime();

      if (elapsed < 60_000) {
        return jsonResponse(
          {
            error:
              "Please wait before requesting another code.",
          },
          429,
        );
      }
    }

    const random = new Uint32Array(1);
    crypto.getRandomValues(random);

    const code =
      ((random[0] % 900000) + 100000).toString();

    const expiresAt =
      new Date(
        Date.now() + 10 * 60_000,
      ).toISOString();

    const {
      error: storeError,
    } = await admin
      .from("emergency_contact_verifications")
      .upsert({
        contact_id: contactId,
        otp_hash: await hashOtp(contactId, code),
        expires_at: expiresAt,
        attempt_count: 0,
        last_sent_at: new Date().toISOString(),
      });

    if (storeError) {
      throw storeError;
    }

    const apiKey =
      Deno.env.get("RESEND_API_KEY");

    const from =
      Deno.env.get("RESEND_FROM_EMAIL");

    if (!apiKey || !from) {
      throw new Error(
        "Email service is not configured",
      );
    }

    const sent = await fetch(
      "https://api.resend.com/emails",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from,
          to: [contact.email],
          subject:
            "TravelEase Emergency Contact Verification",
          text: [
            "TravelEase Emergency Contact Verification",
            "",
            "A TravelEase user has added this email address as their emergency contact.",
            "",
            "Use the verification code below to verify this email address:",
            "",
            `Verification code: ${code}`,
            "",
            "This code expires 10 minutes after it was requested. Please complete verification before it expires.",
            "",
            "Do not share this verification code with anyone.",
            "TravelEase staff will never ask you for this code.",
            "",
            "If you did not expect this request, you may ignore this email.",
            "",
            "TravelEase",
          ].join("\n"),
          html: `
            <div style="padding:24px;background:#f3f4f6;font-family:Arial,sans-serif;color:#1f2937;line-height:1.6">
              <div style="max-width:600px;margin:auto;padding:28px;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px">
                <h1 style="margin:0 0 20px;font-size:24px;line-height:1.3;color:#0f766e">TravelEase Emergency Contact Verification</h1>
                <p>A TravelEase user has added this email address as their emergency contact.</p>
                <p>Use the verification code below to verify this email address:</p>
                <div style="margin:24px 0;padding:20px;text-align:center;background:#f0fdfa;border:1px solid #99f6e4;border-radius:8px">
                  <p style="margin:0 0 8px;font-size:14px;color:#374151">Verification code</p>
                  <p style="margin:0;font-family:Consolas,monospace;font-size:32px;font-weight:bold;letter-spacing:6px;color:#115e59">${code}</p>
                </div>
                <p>This code expires <strong>10 minutes after it was requested</strong>. Please complete verification before it expires.</p>
                <div style="margin:24px 0;padding:16px;background:#f9fafb;border-left:4px solid #0f766e">
                  <p style="margin:0 0 8px"><strong>Do not share this verification code with anyone.</strong></p>
                  <p style="margin:0">TravelEase staff will never ask you for this code.</p>
                </div>
                <p>If you did not expect this request, you may ignore this email.</p>
                <p style="margin-top:24px;padding-top:16px;border-top:1px solid #e5e7eb;font-size:13px;color:#4b5563">TravelEase</p>
              </div>
            </div>`,
        }),
      },
    );

    if (!sent.ok) {
      await admin
        .from("emergency_contact_verifications")
        .delete()
        .eq("contact_id", contactId);

      console.error(
        "Resend delivery failed",
        sent.status,
        await sent.text(),
      );

      return jsonResponse(
        {
          error:
            "The verification email could not be sent.",
        },
        502,
      );
    }

    return jsonResponse({
      success: true,
      expires_at: expiresAt,
    });
  } catch (error) {
    console.error(
      "request-emergency-contact-otp",
      error,
    );

    const unauthorized =
      error instanceof Error &&
      error.message === "Unauthorized";

    return jsonResponse(
      {
        error: unauthorized
          ? "Unauthorized"
          : "Unable to send verification code.",
      },
      unauthorized ? 401 : 500,
    );
  }
});
