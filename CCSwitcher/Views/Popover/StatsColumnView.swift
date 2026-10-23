import SwiftUI

/// Right popover column: promo, compact costs, 14-day list.
/// The shell owns the ScrollView, so this view adds none.
struct StatsColumnView: View {
    var body: some View {
        VStack(spacing: AppStyle.groupSpacing) {
            if DoubleUsagePromo.isCampaignActive() {
                PromoCard()
            }
            TodayCostCard()
            CostHistoryCard()
        }
    }
}
