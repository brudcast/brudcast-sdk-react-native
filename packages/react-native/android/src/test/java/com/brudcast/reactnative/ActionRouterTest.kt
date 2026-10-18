package com.brudcast.reactnative

import com.brudcast.sdk.BrudcastAction
import com.brudcast.sdk.BrudcastActionResult
import com.brudcast.sdk.BrudcastAsyncActionHandler
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class ActionRouterTest {
    private var now = 0L
    private val scheduled = ArrayList<Pair<Long, () -> Unit>>()
    private var installed: BrudcastAsyncActionHandler? = null
    private val defaults = ArrayList<BrudcastAction>()
    private lateinit var router: ActionRouter

    private val tap = BrudcastAction(BrudcastAction.Kind.DEEPLINK, "myapp://checkout", source = BrudcastAction.Source.Push("m1"), verified = false)

    @BeforeTest
    fun setUp() {
        router = ActionRouter(
            clock = { now },
            schedule = { delay, task -> scheduled.add(now + delay to task) },
            install = { installed = it },
            performDefault = { defaults.add(it) },
        )
    }

    private fun advance(to: Long) {
        now = to
        scheduled.filter { it.first <= now }.forEach { scheduled.remove(it); it.second() }
    }

    private fun route(action: BrudcastAction): BrudcastActionResult? {
        var result: BrudcastActionResult? = null
        assertNotNull(installed).handle(action) { result = it }
        return result
    }

    private class RecordingTarget(private val answer: BrudcastActionResult) : ActionRouter.Target {
        val received = ArrayList<BrudcastAction>()

        override fun handle(action: BrudcastAction, decide: (BrudcastActionResult) -> Unit) {
            received.add(action)
            decide(answer)
        }
    }

    @Test
    fun holdsALaunchTapUntilJavaScriptSetsAHandler() {
        router.moduleCreated()
        assertEquals(BrudcastActionResult.HANDLED, route(tap))

        val target = RecordingTarget(BrudcastActionResult.HANDLED)
        advance(1_000)
        router.setTarget(target)

        assertEquals(listOf(tap), target.received)
        assertEquals(emptyList(), defaults)
    }

    @Test
    fun runsTheDefaultWhenTheReplayedHandlerDeclines() {
        router.moduleCreated()
        route(tap)
        router.setTarget(RecordingTarget(BrudcastActionResult.USE_DEFAULT))

        assertEquals(listOf(tap), defaults)
    }

    @Test
    fun runsTheDefaultForHeldTapsWhenTheWindowEnds() {
        router.moduleCreated()
        route(tap)
        advance(ActionRouter.HOLD_MS)

        assertEquals(listOf(tap), defaults)
        assertNull(installed)
    }

    @Test
    fun usesTheDefaultAfterTheWindowWithNoHandler() {
        router.moduleCreated()
        val late = RecordingTarget(BrudcastActionResult.HANDLED)
        router.setTarget(late)
        router.clearTarget(late)
        advance(ActionRouter.HOLD_MS + 1)

        assertNull(installed)
    }

    @Test
    fun sendsActionsStraightToASetHandler() {
        router.moduleCreated()
        val target = RecordingTarget(BrudcastActionResult.HANDLED)
        router.setTarget(target)
        advance(ActionRouter.HOLD_MS)

        assertEquals(BrudcastActionResult.HANDLED, route(tap))
        assertEquals(listOf(tap), target.received)
        assertEquals(emptyList(), defaults)
    }

    @Test
    fun ignoresAClearFromAModuleThatDoesNotOwnTheHandler() {
        router.moduleCreated()
        val owner = RecordingTarget(BrudcastActionResult.HANDLED)
        router.setTarget(owner)
        router.clearTarget(RecordingTarget(BrudcastActionResult.USE_DEFAULT))
        advance(ActionRouter.HOLD_MS)

        route(tap)
        assertEquals(listOf(tap), owner.received)
    }

    @Test
    fun aLaterModuleExtendsTheWindow() {
        router.moduleCreated()
        advance(4_000)
        router.moduleCreated()
        advance(ActionRouter.HOLD_MS)

        assertEquals(BrudcastActionResult.HANDLED, route(tap))
        advance(4_000 + ActionRouter.HOLD_MS)
        assertEquals(listOf(tap), defaults)
    }
}
