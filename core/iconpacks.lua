--[[
    I remember you! -- the curated icon library.

    The game cannot enumerate files, so this table is the manifest: every icon
    we are allowed to show is listed here by hand. It is data only -- no game
    calls, no validation at load time; IRY.Icons validates paths lazily.

    To add a pack:

        {
            id    = "base",
            title = "Base",
            icons = {
                "IRememberYou/icons/base/skull.dds",
                "IRememberYou/icons/base/wolf.dds",
            },
        }

    Every path must be lowercase, under IRememberYou/icons/<pack>/, and a .dds
    file. The default marker for ignored players is IRY.ICON.blacklistDefault
    (rooster.dds), so that file must stay listed; an explicit choice in the
    settings always wins over it.

    The shipped pack is `base`: 75 icons, 128 x 128 DXT5 with mipmaps, 1.6 MB in
    total. 64 x 64 also renders fine -- the UI scales them down to 16-40 px and
    the 3D size comes from OdySupportIcons.

    Icons live inside our addon on purpose: pointing at another addon's folder
    would make our 2D icons disappear together with that addon.
]]

IRY.IconPacks = {
    {
        id    = "base",
        title = "Library",
        icons = {
            "IRememberYou/icons/base/skull.dds",
            "IRememberYou/icons/base/arrow.dds",
            "IRememberYou/icons/base/arrow-yellow.dds",
            "IRememberYou/icons/base/cat.dds",
            "IRememberYou/icons/base/cat_alex.dds",
            "IRememberYou/icons/base/cat_ok.dds",
            "IRememberYou/icons/base/di-caprio.dds",
            "IRememberYou/icons/base/dog.dds",
            "IRememberYou/icons/base/doge.dds",
            "IRememberYou/icons/base/emodzi-angeryscimitar.dds",
            "IRememberYou/icons/base/emodzi-angrypepeak47.dds",
            "IRememberYou/icons/base/emodzi-cheemsdoge.dds",
            "IRememberYou/icons/base/emodzi-cooldoge.dds",
            "IRememberYou/icons/base/emodzi-cryingpanda.dds",
            "IRememberYou/icons/base/emodzi-dogegun.dds",
            "IRememberYou/icons/base/emodzi-dogetripoloski.dds",
            "IRememberYou/icons/base/emodzi-doge-with-gun.dds",
            "IRememberYou/icons/base/emodzi-ezpepe.dds",
            "IRememberYou/icons/base/emodzi-facepalm.dds",
            "IRememberYou/icons/base/emodzi-honkler_clown.dds",
            "IRememberYou/icons/base/emodzi-keanucyberpunkonguitar.dds",
            "IRememberYou/icons/base/emodzi-keanureevescyberpunk.dds",
            "IRememberYou/icons/base/emodzi-monkagun.dds",
            "IRememberYou/icons/base/emodzi-pandaadmire.dds",
            "IRememberYou/icons/base/emodzi-pandacool.dds",
            "IRememberYou/icons/base/emodzi-pandadisgust.dds",
            "IRememberYou/icons/base/emodzi-pandauh.dds",
            "IRememberYou/icons/base/emodzi-peepo-ban.dds",
            "IRememberYou/icons/base/emodzi-peepolove.dds",
            "IRememberYou/icons/base/emodzi-peepo-no.dds",
            "IRememberYou/icons/base/emodzi-pepe_toxic2008.dds",
            "IRememberYou/icons/base/emodzi-pepe-cool.dds",
            "IRememberYou/icons/base/emodzi-pepecry.dds",
            "IRememberYou/icons/base/emodzi-pepe-reeeeeeeeeeeee.dds",
            "IRememberYou/icons/base/emodzi-pepe-yes.dds",
            "IRememberYou/icons/base/emodzi-strong-doge.dds",
            "IRememberYou/icons/base/emodzi-takeoffglasses.dds",
            "IRememberYou/icons/base/emodzi-whatthefuck.dds",
            "IRememberYou/icons/base/engineer2.dds",
            "IRememberYou/icons/base/engineer2-jpg.dds",
            "IRememberYou/icons/base/fire.dds",
            "IRememberYou/icons/base/flake.dds",
            "IRememberYou/icons/base/green_arrow.dds",
            "IRememberYou/icons/base/harold.dds",
            "IRememberYou/icons/base/heart.dds",
            "IRememberYou/icons/base/hide-the-pain-harold.dds",
            "IRememberYou/icons/base/jonnykreng.dds",
            "IRememberYou/icons/base/leaf.dds",
            "IRememberYou/icons/base/lighning.dds",
            "IRememberYou/icons/base/lion.dds",
            "IRememberYou/icons/base/mandalorian.dds",
            "IRememberYou/icons/base/ok.dds",
            "IRememberYou/icons/base/opossum.dds",
            "IRememberYou/icons/base/p_xiraaka88.dds",
            "IRememberYou/icons/base/paw.dds",
            "IRememberYou/icons/base/paw-blue.dds",
            "IRememberYou/icons/base/pelenal.dds",
            "IRememberYou/icons/base/penguin.dds",
            "IRememberYou/icons/base/pepe.dds",
            "IRememberYou/icons/base/pepe-cry.dds",
            "IRememberYou/icons/base/risitas.dds",
            "IRememberYou/icons/base/roger.dds",
            "IRememberYou/icons/base/rooster.dds",
            "IRememberYou/icons/base/skyrim.dds",
            "IRememberYou/icons/base/staridnova.dds",
            "IRememberYou/icons/base/storm.dds",
            "IRememberYou/icons/base/sun.dds",
            "IRememberYou/icons/base/sword.dds",
            "IRememberYou/icons/base/sword-blue.dds",
            "IRememberYou/icons/base/sword-fire.dds",
            "IRememberYou/icons/base/sword-rainbow.dds",
            "IRememberYou/icons/base/tegaro.dds",
            "IRememberYou/icons/base/trollface.dds",
            "IRememberYou/icons/base/wolf.dds",
            "IRememberYou/icons/base/yoga.dds",
        },
    },
}
