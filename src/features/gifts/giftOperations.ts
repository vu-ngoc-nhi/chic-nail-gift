import type { ChicSupabaseClient } from '../../lib/supabase.ts'
import type { CreateGiftResult } from './giftPresentation.ts'

export class GiftOperationError extends Error {
  readonly kind: 'unauthorized' | 'request-failed'

  constructor(kind: 'unauthorized' | 'request-failed') {
    super(kind)
    this.name = 'GiftOperationError'
    this.kind = kind
  }
}

export async function createGift(
  client: ChicSupabaseClient,
  billCode: string,
  billAmountVnd: number,
) {
  const { data, error } = await client.rpc('create_gift', {
    p_bill_code: billCode,
    p_bill_amount_vnd: billAmountVnd,
  })

  if (error) {
    throw new GiftOperationError(error.code === '42501' ? 'unauthorized' : 'request-failed')
  }

  const result = (Array.isArray(data) ? data[0] : data) as CreateGiftResult | undefined
  if (!result?.result_code) {
    throw new GiftOperationError('request-failed')
  }

  return result
}
