import { Request, Response, NextFunction, RequestHandler } from 'express';
import { prisma } from '../db/prisma';

async function checkSuspendedImpl(req: Request, res: Response, next: NextFunction) {
  const sub = req.user?.sub;
  if (!sub) return next();

  const user = await prisma.user.findUnique({ where: { cognitoSub: sub }, select: { suspended: true } });
  if (user?.suspended) {
    return res.status(403).json({ error: { code: 'ACCOUNT_SUSPENDED', message: 'Your account has been suspended' } });
  }
  next();
}

export const checkSuspended: RequestHandler = (req, res, next) => {
  checkSuspendedImpl(req, res, next).catch(next);
};

export function withSuspendCheck(handler: RequestHandler): RequestHandler[] {
  return [checkSuspended, handler];
}
