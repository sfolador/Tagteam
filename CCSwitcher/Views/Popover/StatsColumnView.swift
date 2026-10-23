import SwiftUI

/// Right popover column: promo, today's cost, activity, cost history.
/// The shell owns the ScrollView, so this view adds none.
struct StatsColumnView: View {
    var body: some View {
        VStack(spacing: AppStyle.groupSpacing) {
            if DoubleUsagePromo.isCampaignActive() {
                PromoCard()
            }
            TodayCostCard()
            ActivityCard()
            CostHistoryCard()
        }
    }
}
