import { Request, Response, NextFunction } from 'express';
import { prisma } from '../db/prisma';

export const checkSuspended = async (req: Request, res: Response, next: NextFunction) => {
  const sub = req.user?.sub;
  if (!sub) return next();

  const user = await prisma.user.findUnique({ where: { cognitoSub: sub }, select: { suspended: true } });
  if (user?.suspended) {
    return res.status(403).json({ error: { code: 'ACCOUNT_SUSPENDED', message: 'Your account has been suspended' } });
  }
  next();
};
