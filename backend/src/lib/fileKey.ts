import { Errors } from "./errors";

// POST /uploads/presign always issues keys as `${sub}/${uuid}-${fileName}`
// (see uploads.routes.ts). Any endpoint that registers a fileKey's metadata
// (a document, a vehicle photo) must not trust the client-supplied string
// at face value — this is the server-side check that a fileKey a driver is
// registering was actually issued to *them*, not copied/guessed from
// another user's namespace.
export function assertFileKeyOwnedByUser(fileKey: string, cognitoSub: string) {
  if (!fileKey.startsWith(`${cognitoSub}/`)) {
    throw Errors.authorization("This file was not uploaded by you.");
  }
}
