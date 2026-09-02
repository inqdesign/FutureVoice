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
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.WorkOutline
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
        // `SituationTree`'s own names — the same symbols with `.fill`, which
        // SF Symbols treats as a variant of one glyph and Material does not.
        "cup.and.saucer.fill" to Icons.Filled.LocalCafe,
        "briefcase.fill" to Icons.Filled.Business,
        "cross.case.fill" to Icons.Filled.LocalHospital,
        "bag.fill" to Icons.Filled.LocalMall,
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
