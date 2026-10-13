package com.roro.futurevoice.ui.brand

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.LocalMall
import androidx.compose.material.icons.filled.Train
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.WavingHand
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.WorkOutline
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AccountBox
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.Feedback
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.automirrored.filled.Help
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.EmojiPeople
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Mic
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * SF Symbol name → Material icon, in ONE table.
 *
 * The server and the shared content files speak SF Symbols: `TopicClient`'s
 * icon palette is the list the categorizer must choose from, and
 * `SituationTree` carries the names extracted from the Swift source. Both are
 * cross-platform contracts, so Android cannot rename them — it translates
 * them here instead, once.
 *
 * Centralized for the same reason iOS keeps `Books.roleIcon` in one place: a
 * per-screen `when` block is how two surfaces end up drawing the same
 * category with different icons.
 *
 * An unknown name falls back to [fallback] rather than drawing nothing — the
 * palette can grow server-side without shipping a client.
 */
object Symbols {

    val fallback: ImageVector = Icons.Filled.AutoAwesome

    private val table: Map<String, ImageVector> = mapOf(
        // The categorizer's palette (`TopicClient.ICON_PALETTE`).
        "cup.and.saucer" to Icons.Filled.LocalCafe,
        "fork.knife" to Icons.Filled.Restaurant,
        "cart" to Icons.Filled.ShoppingCart,
        "briefcase" to Icons.Filled.WorkOutline,
        "stethoscope" to Icons.Filled.LocalHospital,
        "airplane" to Icons.Filled.Flight,
        "house" to Icons.Filled.Home,
        "graduationcap" to Icons.Filled.School,
        "phone" to Icons.Filled.Phone,
        "person.2" to Icons.Filled.People,
        "car" to Icons.Filled.DirectionsCar,
        "banknote" to Icons.Filled.Payments,
        "heart" to Icons.Filled.Favorite,
        "sparkles" to Icons.Filled.AutoAwesome,
        // The rest of iOS's palette (`ScenarioIconPalette`, generated).
        "building.2" to Icons.Filled.Apartment,
        "gift" to Icons.Filled.CardGiftcard,
        "figure.wave" to Icons.Filled.EmojiPeople,
        "dumbbell" to Icons.Filled.FitnessCenter,
        "pawprint" to Icons.Filled.Pets,
        "music.mic" to Icons.Filled.Mic,
        // `SituationTree`'s own names — the same symbols with `.fill`, which
        // SF Symbols treats as a variant of one glyph and Material does not.
        "cup.and.saucer.fill" to Icons.Filled.LocalCafe,
        "briefcase.fill" to Icons.Filled.Business,
        "cross.case.fill" to Icons.Filled.LocalHospital,
        "bag.fill" to Icons.Filled.LocalMall,
        // Talk's Everyday situations (`StarterSituation`).
        "hand.wave" to Icons.Filled.WavingHand,
        "map" to Icons.Filled.Map,
        "bed.double" to Icons.Filled.Hotel,
        "tram" to Icons.Filled.Train,
        // Talk's purpose chips (`LearningPurpose`, `StarterSituation`'s
        // interview / work / life / travel sets) and the purpose rows.
        "person.crop.square" to Icons.Filled.AccountBox,
        "questionmark.bubble" to Icons.AutoMirrored.Filled.Help,
        "chart.bar" to Icons.Filled.BarChart,
        "person.3" to Icons.Filled.Groups,
        "chart.line.uptrend.xyaxis" to Icons.AutoMirrored.Filled.TrendingUp,
        "key" to Icons.Filled.Key,
        "building.columns" to Icons.Filled.AccountBalance,
        "figure.and.child.holdinghands" to Icons.Filled.FamilyRestroom,
        "exclamationmark.bubble" to Icons.Filled.Feedback,
        "bubble.left.and.bubble.right" to Icons.Filled.Forum,
        "checklist" to Icons.Filled.Checklist,
        "person.text.rectangle" to Icons.Filled.Badge,
        "book" to Icons.AutoMirrored.Filled.MenuBook,
        "square.and.pencil" to Icons.Filled.EditNote,
    )

    /**
     * The icon for an SF Symbol name. A `.fill` suffix is stripped before the
     * second lookup, so a new filled variant on the server resolves to the
     * same glyph instead of falling through to the sparkle.
     */
    fun icon(name: String?): ImageVector {
        if (name.isNullOrBlank()) return fallback
        table[name]?.let { return it }
        return table[name.removeSuffix(".fill")] ?: fallback
    }
}
