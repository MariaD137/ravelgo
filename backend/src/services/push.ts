import { PinpointClient, SendMessagesCommand, type AddressConfiguration } from "@aws-sdk/client-pinpoint";
import { env } from "../config/env";
import { prisma } from "../db/prisma";

const pinpoint = new PinpointClient({ region: env.AWS_REGION });

function channelTypeFor(platform: string): "APNS" | "GCM" {
  return platform === "IOS" ? "APNS" : "GCM";
}

// Delivery statuses Pinpoint will never retry on its own — the token is
// permanently dead (app uninstalled, user opted out, or was never valid),
// so this is the "invalid/expired token cleanup" the notification pipeline
// travels through, rather than paying for (and re-attempting) a doomed send
// on every future event forever.
const DEAD_TOKEN_STATUSES = new Set(["PERMANENT_FAILURE", "OPT_OUT"]);

/**
 * Fan a push out to every device this user has registered (see PushToken),
 * via AWS Pinpoint — the same AWS account/IAM role as everything else in
 * this backend, no separate provider SDK or credential set. Best-effort and
 * never throws: mirrors notifyUser's own contract, since a push failure must
 * never fail the real backend event (a completed ride, a delivered package)
 * that triggered it. Pinpoint sends directly to the raw device token (no
 * pre-registered "endpoint" resource needed, unlike SNS Mobile Push), so
 * registering a token is just a database write — see notifications.routes.ts.
 */
export async function sendPushToUser(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string> = {},
): Promise<void> {
  if (!env.PINPOINT_APPLICATION_ID) return; // push not configured for this deploy — in-app notification already persisted separately

  try {
    const tokens = await prisma.pushToken.findMany({ where: { userId } });
    if (tokens.length === 0) return;

    const addresses: Record<string, AddressConfiguration> = {};
    for (const t of tokens) {
      addresses[t.token] = { ChannelType: channelTypeFor(t.platform) };
    }

    const response = await pinpoint.send(
      new SendMessagesCommand({
        ApplicationId: env.PINPOINT_APPLICATION_ID,
        MessageRequest: {
          Addresses: addresses,
          MessageConfiguration: {
            GCMMessage: { Title: title, Body: body, Data: data },
            APNSMessage: { Title: title, Body: body, Data: data, Sound: "default" },
          },
        },
      }),
    );

    const results = response.MessageResponse?.Result ?? {};
    const deadTokens = Object.entries(results)
      .filter(([, result]) => result.DeliveryStatus && DEAD_TOKEN_STATUSES.has(result.DeliveryStatus))
      .map(([address]) => address);
    if (deadTokens.length > 0) {
      await prisma.pushToken.deleteMany({ where: { token: { in: deadTokens } } }).catch(() => {});
    }
  } catch (err) {
    // Guarantees the "never throws" contract even if Pinpoint itself is
    // unreachable or misconfigured — a push failure must never fail the
    // real backend event that triggered it.
    console.error("Failed to send push notification", err);
  }
}
