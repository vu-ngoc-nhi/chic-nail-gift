import { useEffect, useState } from 'react'
import { CUSTOMER_BRAND_NAME } from '../../config/presentation.ts'
import { supabase, supabaseConfigurationError } from '../../lib/supabase.ts'
import {
  getPublicGift,
  presentPublicGift,
  type PublicGiftResult,
} from './publicGift.ts'

type PublicGiftPageProps = {
  giftToken: string
}

export function PublicGiftPage({ giftToken }: PublicGiftPageProps) {
  const [result, setResult] = useState<PublicGiftResult | null>(null)
  const [loading, setLoading] = useState(Boolean(supabase && !supabaseConfigurationError))
  const [requestFailed, setRequestFailed] = useState(Boolean(!supabase || supabaseConfigurationError))

  useEffect(() => {
    let active = true

    if (!supabase || supabaseConfigurationError) {
      return () => {
        active = false
      }
    }

    void getPublicGift(supabase, giftToken)
      .then((gift) => {
        if (active) {
          setResult(gift)
          setLoading(false)
        }
      })
      .catch(() => {
        if (active) {
          setRequestFailed(true)
          setLoading(false)
        }
      })

    return () => {
      active = false
    }
  }, [giftToken])

  if (loading) {
    return (
      <main className="customer-shell" aria-busy="true">
        <section className="customer-card customer-card--centered">
          <p className="customer-brand">{CUSTOMER_BRAND_NAME}</p>
          <span className="loading-dot" aria-hidden="true" />
          <h1>Đang chuẩn bị phần quà…</h1>
        </section>
      </main>
    )
  }

  if (requestFailed || !result) {
    return (
      <main className="customer-shell">
        <section className="customer-card customer-card--centered" role="alert">
          <p className="customer-brand">{CUSTOMER_BRAND_NAME}</p>
          <h1>Chưa thể tải phần quà.</h1>
          <p>Vui lòng kiểm tra kết nối và thử quét lại mã QR.</p>
        </section>
      </main>
    )
  }

  const presentation = presentPublicGift(result)

  return (
    <main className="customer-shell">
      <article className={`customer-card customer-card--${presentation.tone}`}>
        <p className="customer-brand">{CUSTOMER_BRAND_NAME}</p>

        {presentation.showCampaign && result.campaign_headline && (
          <p className="customer-kicker">DÀNH RIÊNG CHO BẠN</p>
        )}

        <h1>{result.campaign_headline && presentation.showCampaign
          ? result.campaign_headline
          : presentation.title}</h1>

        {presentation.showCampaign && (
          <p className="customer-status">{presentation.title}</p>
        )}
        <p className="customer-message">{presentation.message}</p>

        {presentation.showCampaign && result.campaign_description && (
          <p className="customer-description">{result.campaign_description}</p>
        )}

        {presentation.showCampaign && result.campaign_terms && (
          <section className="customer-terms" aria-labelledby="campaign-terms-title">
            <h2 id="campaign-terms-title">Điều kiện chương trình</h2>
            <p>{result.campaign_terms}</p>
          </section>
        )}

        {presentation.showFutureAction && (
          <div className="future-action" aria-disabled="true">
            Mở quà sẽ được kích hoạt ở bước tiếp theo.
          </div>
        )}
      </article>
    </main>
  )
}
