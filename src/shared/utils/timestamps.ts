export const now = (): string => new Date().toISOString();

export const toIso = (date: Date): string => date.toISOString();

export const parseIso = (iso: string): Date => new Date(iso);
