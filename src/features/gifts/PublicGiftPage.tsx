import { useCallback, useEffect, useRef, useState } from 'react'
import { CUSTOMER_BRAND_NAME } from '../../config/presentation.ts'
import { supabase, supabaseConfigurationError } from '../../lib/supabase.ts'
import {
  getOpeningDelay,
  isRewardResult,
  lockSecretCardSelection,
  openGift,
  presentOpenGiftUnavailable,
  presentReward,
  SECRET_CARD_COUNT,
  type OpenGiftResult,
} from './customerGift.ts'
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
  const [selectedCard, setSelectedCard] = useState<number | null>(null)
  const [openingState, setOpeningState] = useState<'idle' | 'opening' | 'retry' | 'unavailable'>('idle')
  const [reward, setReward] = useState<OpenGiftResult | null>(null)
  const [openUnavailable, setOpenUnavailable] = useState<ReturnType<typeof presentOpenGiftUnavailable> | null>(null)
  const [copyMessage, setCopyMessage] = useState('')
  const selectionLocked = useRef(false)

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

  const requestReward = useCallback(async (withOpeningMoment: boolean) => {
    if (!supabase || supabaseConfigurationError) {
      setOpeningState('retry')
      return
    }

    setOpeningState('opening')

    const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false
    const openingDelay = getOpeningDelay(reduceMotion, withOpeningMoment)
    const minimumMoment = openingDelay > 0
      ? new Promise<void>((resolve) => window.setTimeout(resolve, openingDelay))
      : Promise.resolve()

    try {
      const request = openGift(supabase, giftToken)
      const [openResult] = await Promise.all([request, minimumMoment])

      if (isRewardResult(openResult)) {
        setReward(openResult)
        setOpeningState('idle')
        return
      }

      setOpenUnavailable(presentOpenGiftUnavailable(openResult.result_code))
      setOpeningState('unavailable')
    } catch {
      setOpeningState('retry')
    }
  }, [giftToken])

  useEffect(() => {
    if (result?.result_code !== 'GIFT_OPENED' || selectionLocked.current) {
      return
    }

    selectionLocked.current = true
    void requestReward(false)
  }, [requestReward, result])

  function handleCardSelection(cardIndex: number) {
    if (selectionLocked.current || openingState !== 'idle') {
      return
    }

    selectionLocked.current = true
    setSelectedCard((currentSelection) => lockSecretCardSelection(currentSelection, cardIndex))
    void requestReward(true)
  }

  async function copyRewardCode() {
    if (!reward?.reward_code) {
      return
    }

    try {
      await navigator.clipboard.writeText(reward.reward_code)
      setCopyMessage('Đã sao chép mã quà.')
    } catch {
      setCopyMessage('Chưa thể sao chép. Vui lòng nhấn giữ để chọn mã.')
    }
  }

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

  if (reward && isRewardResult(reward)) {
    const rewardPresentation = presentReward(reward)
    const revisited = reward.result_code === 'ALREADY_OPENED'

    return (
      <main className="customer-shell">
        <article className="customer-card customer-card--reward">
          <p className="customer-brand">{CUSTOMER_BRAND_NAME}</p>
          <p className="customer-kicker">QUÀ DÀNH CHO BẠN</p>
          <h1>{reward.reward_name}</h1>
          {revisited && (
            <p className="customer-revisit-note">Đây là phần quà bạn đã mở trước đó.</p>
          )}
          <p className="reward-benefit">{rewardPresentation.benefit}</p>
          {rewardPresentation.description && (
            <p className="customer-description">{rewardPresentation.description}</p>
          )}

          <section className="reward-code" aria-labelledby="reward-code-title">
            <p id="reward-code-title">Mã quà của bạn</p>
            <strong>{reward.reward_code}</strong>
            <p>Giữ lại mã này để sử dụng tại {CUSTOMER_BRAND_NAME}.</p>
            <button className="button button--secondary" type="button" onClick={() => void copyRewardCode()}>
              SAO CHÉP MÃ
            </button>
            {copyMessage && <p className="copy-status" role="status">{copyMessage}</p>}
          </section>

          <dl className="reward-details">
            <div>
              <dt>Hạn sử dụng</dt>
              <dd>{rewardPresentation.expiry}</dd>
            </div>
            {rewardPresentation.applicableService && (
              <div>
                <dt>Áp dụng</dt>
                <dd>{rewardPresentation.applicableService}</dd>
              </div>
            )}
            {rewardPresentation.minimumSpend && (
              <div>
                <dt>Điều kiện hóa đơn</dt>
                <dd>{rewardPresentation.minimumSpend}</dd>
              </div>
            )}
            {rewardPresentation.discountPercent && (
              <div>
                <dt>Mức ưu đãi</dt>
                <dd>{rewardPresentation.discountPercent}</dd>
              </div>
            )}
          </dl>

          {rewardPresentation.terms && (
            <section className="customer-terms" aria-labelledby="reward-terms-title">
              <h2 id="reward-terms-title">Điều kiện sử dụng</h2>
              <p>{rewardPresentation.terms}</p>
            </section>
          )}
        </article>
      </main>
    )
  }

  if (openUnavailable) {
    return (
      <main className="customer-shell">
        <section className="customer-card customer-card--centered customer-card--unavailable" role="alert">
          <p className="customer-brand">{CUSTOMER_BRAND_NAME}</p>
          <h1>{openUnavailable.title}</h1>
          <p>{openUnavailable.message}</p>
        </section>
      </main>
    )
  }

  if (result.result_code === 'GIFT_OPENED') {
    return (
      <main className="customer-shell" aria-busy={openingState === 'opening'}>
        <section className="customer-card customer-card--centered" aria-live="polite">
          <p className="customer-brand">{CUSTOMER_BRAND_NAME}</p>
          <span className="loading-dot" aria-hidden="true" />
          <h1>{openingState === 'retry' ? 'Chưa tải được kết quả quà.' : 'Đang tải quà của bạn…'}</h1>
          {openingState === 'retry' && (
            <button className="button button--primary" type="button" onClick={() => void requestReward(false)}>
              THỬ LẠI
            </button>
          )}
        </section>
      </main>
    )
  }

  if (result.result_code === 'GIFT_AVAILABLE' && result.may_open) {
    return (
      <main className="customer-shell">
        <article className="customer-card customer-card--gift-choice">
          <p className="customer-brand">{CUSTOMER_BRAND_NAME}</p>
          {result.campaign_headline && <p className="customer-kicker">DÀNH RIÊNG CHO BẠN</p>}
          <h1>{result.campaign_headline || 'Món quà dành cho bạn'}</h1>
          <p className="customer-instruction">Chọn một phong bì bạn thấy có duyên nhất ✨</p>
          <p className="customer-message">Món quà dành cho bạn đang chờ được mở.</p>

          <div className="secret-card-grid" aria-label="Chín phong bì quà">
            {Array.from({ length: SECRET_CARD_COUNT }, (_, index) => {
              const isSelected = selectedCard === index
              const isLocked = selectedCard !== null

              return (
                <button
                  aria-label={`Phong bì ${index + 1}${isSelected ? ', đã chọn' : ''}`}
                  aria-pressed={isSelected}
                  className={`secret-card${isSelected ? ' secret-card--selected' : ''}`}
                  disabled={isLocked}
                  key={index}
                  onClick={() => handleCardSelection(index)}
                  type="button"
                >
                  <span className="secret-card__flap" aria-hidden="true" />
                  <span className="secret-card__mark" aria-hidden="true">CG</span>
                  <span className="secret-card__label">{isSelected ? 'Đã chọn' : 'Mở quà'}</span>
                </button>
              )
            })}
          </div>

          <div className="opening-status" aria-live="polite">
            {openingState === 'opening' && (
              <>
                <span className="loading-dot" aria-hidden="true" />
                <p>Đang mở quà của bạn…</p>
              </>
            )}
            {openingState === 'retry' && (
              <>
                <p className="opening-error">Chưa tải được kết quả quà.</p>
                <button className="button button--primary" type="button" onClick={() => void requestReward(false)}>
                  THỬ LẠI
                </button>
              </>
            )}
          </div>

          {result.campaign_description && (
            <p className="customer-description customer-description--compact">{result.campaign_description}</p>
          )}
        </article>
      </main>
    )
  }

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
