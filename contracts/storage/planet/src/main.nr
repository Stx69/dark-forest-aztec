// Storage contract for planet state (meta, owner, caps, resources, mods, etc.).
// Only admin or authorized contracts can write; anyone can verify state by hash.

#[::types::storage::state::game_contract]
pub contract PlanetStorage {
    use ::aztec::{
        macros::{
            events::event,
            functions::{external, initializer, internal, view},
            storage::storage,
        },
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::Serialize},
    };

    use ::aztec::state_vars::{Map, PublicMutable};
    use ::types::storage::planet::{Planet, PlanetSplitRoots};

    #[storage]
    struct Storage<Context> {
        // Admin and authorized callers (only they can write; read is public).
        admin: PublicMutable<AztecAddress, Context>,
        authorized_map: Map<AztecAddress, PublicMutable<bool, Context>, Context>,
        authorized_index: Map<AztecAddress, PublicMutable<u32, Context>, Context>,
        authorized_list: Map<u32, PublicMutable<AztecAddress, Context>, Context>,
        authorized_count: PublicMutable<u32, Context>,
        // id (e.g. location_id) -> poseidon2 hash of Planet
        state_roots: Map<Field, PublicMutable<Field, Context>, Context>,
        // Versioned split roots. The legacy root above remains authoritative
        // for historical events while new writes dual-publish these roots.
        static_roots: Map<Field, PublicMutable<Field, Context>, Context>,
        dynamic_roots: Map<Field, PublicMutable<Field, Context>, Context>,
        stats_roots: Map<Field, PublicMutable<Field, Context>, Context>,
        modifier_roots: Map<Field, PublicMutable<Field, Context>, Context>,
        composed_roots: Map<Field, PublicMutable<Field, Context>, Context>,
    }

    #[event]
    #[::types::storage::state::state_update]
    struct PlanetUpdate {
        id: Field,
        block_number: u32,
        state: Planet,
    }

    #[event]
    #[::types::storage::state::state_update]
    struct PlanetSplitRootsUpdate {
        id: Field,
        block_number: u32,
        state: PlanetSplitRoots,
    }

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress) {
        self.storage.admin.write(admin);
        self.storage.authorized_count.write(0);
    }

    // ================== INTERNAL AUTH ==================

    #[internal("public")]
    fn assert_admin() {
        assert(self.msg_sender() == self.storage.admin.read(), "Only admin");
    }

    #[internal("public")]
    fn assert_authorized() {
        let caller = self.msg_sender();
        let is_authorized = self.storage.authorized_map.at(caller).read();
        if !is_authorized {
            assert(caller == self.storage.admin.read(), "Not authorized");
        }
    }

    // ================== ADD / UPDATE ==================

    #[external("public")]
    fn set(id: Field, planet: Planet) {
        // 15 marks every slice dirty. Existing callers keep the full write.
        self.internal.write_planet(id, planet, 15);
    }

    /// Write the full planet log, and hash only the slices named by `mask`.
    ///
    /// Bits: 1 static, 2 dynamic, 4 stats, 8 modifiers. A clear bit reuses the
    /// root already stored for that slice. The private circuit must set those
    /// bits from a field comparison of the authenticated planet and the new one.
    #[external("public")]
    fn set_slices(id: Field, planet: Planet, mask: u8) {
        self.internal.write_planet(id, planet, mask);
    }

    #[internal("public")]
    fn write_planet(id: Field, planet: Planet, mask: u8) {
        self.internal.assert_authorized();
        assert((mask & 15) == mask, "invalid planet slice mask");
        let block_number = self.context.block_number();
        let (root, log) = PlanetUpdate::encode_update(id, block_number, planet);
        self.storage.state_roots.at(id).write(root);
        let clear_all = planet == Planet::zero();
        let write_static = clear_all | ((mask & 1) == 1);
        let write_dynamic = clear_all | ((mask & 2) == 2);
        let write_stats = clear_all | ((mask & 4) == 4);
        let write_modifiers = clear_all | ((mask & 8) == 8);
        let split_roots = if clear_all {
            PlanetSplitRoots::zero()
        } else {
            let static_root = if write_static {
                poseidon2_hash(planet.split_static().serialize())
            } else {
                self.storage.static_roots.at(id).read()
            };
            let dynamic_root = if write_dynamic {
                poseidon2_hash(planet.split_dynamic().serialize())
            } else {
                self.storage.dynamic_roots.at(id).read()
            };
            let stats_root = if write_stats {
                poseidon2_hash(planet.split_stats().serialize())
            } else {
                self.storage.stats_roots.at(id).read()
            };
            let modifier_root = if write_modifiers {
                poseidon2_hash(planet.split_modifiers().serialize())
            } else {
                self.storage.modifier_roots.at(id).read()
            };
            let composed_root =
                poseidon2_hash([static_root, dynamic_root, stats_root, modifier_root]);
            PlanetSplitRoots { static_root, dynamic_root, stats_root, modifier_root, composed_root }
        };
        if write_static {
            self.storage.static_roots.at(id).write(split_roots.static_root);
        }
        if write_dynamic {
            self.storage.dynamic_roots.at(id).write(split_roots.dynamic_root);
        }
        if write_stats {
            self.storage.stats_roots.at(id).write(split_roots.stats_root);
        }
        if write_modifiers {
            self.storage.modifier_roots.at(id).write(split_roots.modifier_root);
        }
        if clear_all | (mask != 0) {
            self.storage.composed_roots.at(id).write(split_roots.composed_root);
            self.emit(PlanetSplitRootsUpdate { id, block_number, state: split_roots });
        }
        unsafe {
            aztec::oracle::avm::emit_public_log(log.as_vector());
        }
    }

    // ================== ADMIN ==================

    #[external("public")]
    fn transfer_admin(new_admin: AztecAddress) {
        self.internal.assert_admin();
        self.storage.admin.write(new_admin);
    }

    #[external("public")]
    fn add_authorized_contract(contract_address: AztecAddress) {
        self.internal.assert_admin();
        assert(!self.storage.authorized_map.at(contract_address).read(), "Already authorized");

        let count = self.storage.authorized_count.read();
        self.storage.authorized_map.at(contract_address).write(true);
        self.storage.authorized_index.at(contract_address).write(count);
        self.storage.authorized_list.at(count).write(contract_address);
        self.storage.authorized_count.write(count + 1);
    }

    #[external("public")]
    fn remove_authorized_contract(contract_address: AztecAddress) {
        self.internal.assert_admin();
        assert(self.storage.authorized_map.at(contract_address).read(), "Not authorized");

        let index = self.storage.authorized_index.at(contract_address).read();
        let last_index = self.storage.authorized_count.read() - 1;
        self.storage.authorized_map.at(contract_address).write(false);
        self.storage.authorized_index.at(contract_address).write(0);

        if index != last_index {
            let last_contract = self.storage.authorized_list.at(last_index).read();
            self.storage.authorized_list.at(index).write(last_contract);
            self.storage.authorized_index.at(last_contract).write(index);
        }

        self.storage.authorized_list.at(last_index).write(AztecAddress::zero());
        self.storage.authorized_count.write(last_index);
    }

    /// Batch authorize up to 3 contracts in a single transaction.
    #[external("public")]
    fn add_authorized_contracts_batch(addresses: [AztecAddress; 3], count: u8) {
        self.internal.assert_admin();
        assert(count <= 3, "count exceeds batch size");
        let mut current_count = self.storage.authorized_count.read();
        for i in 0..3 {
            if (i as u8) < count {
                let addr = addresses[i];
                assert(!self.storage.authorized_map.at(addr).read(), "Already authorized");
                self.storage.authorized_map.at(addr).write(true);
                self.storage.authorized_index.at(addr).write(current_count);
                self.storage.authorized_list.at(current_count).write(addr);
                current_count += 1;
            }
        }
        self.storage.authorized_count.write(current_count);
    }

    // ================== PUBLIC VIEWS ==================

    #[external("public")]
    #[view]
    fn verify(id: Field, state: Planet) -> bool {
        let stored_hash = self.storage.state_roots.at(id).read();
        if stored_hash == 0 {
            state == Planet::zero()
        } else {
            let computed_hash = poseidon2_hash(state.serialize());
            computed_hash == stored_hash
        }
    }

    #[external("public")]
    #[view]
    fn compute_state_hash(state: Planet) -> Field {
        if (state == Planet::zero()) {
            0
        } else {
            poseidon2_hash(state.serialize())
        }
    }

    #[external("public")]
    #[view]
    fn is_initialized(id: Field) -> bool {
        let stored_hash = self.storage.state_roots.at(id).read();
        stored_hash != 0
    }

    #[external("public")]
    #[view]
    fn get_state_root(id: Field) -> Field {
        self.storage.state_roots.at(id).read()
    }

    #[external("public")]
    #[view]
    fn get_split_roots(id: Field) -> (Field, Field, Field, Field, Field) {
        (
            self.storage.static_roots.at(id).read(), self.storage.dynamic_roots.at(id).read(),
            self.storage.stats_roots.at(id).read(), self.storage.modifier_roots.at(id).read(),
            self.storage.composed_roots.at(id).read(),
        )
    }

    #[external("public")]
    #[view]
    fn verify_split_roots(
        id: Field,
        static_root: Field,
        dynamic_root: Field,
        stats_root: Field,
        modifier_root: Field,
        composed_root: Field,
    ) -> bool {
        (self.storage.static_roots.at(id).read() == static_root)
            & (self.storage.dynamic_roots.at(id).read() == dynamic_root)
            & (self.storage.stats_roots.at(id).read() == stats_root)
            & (self.storage.modifier_roots.at(id).read() == modifier_root)
            & (self.storage.composed_roots.at(id).read() == composed_root)
    }

    #[external("public")]
    #[view]
    fn verify_hash(id: Field, hash: Field) -> bool {
        let stored_hash = self.storage.state_roots.at(id).read();
        stored_hash == hash
    }

    // ================== UTILITY (UNCONSTRAINED) ==================

    #[external("utility")]
    unconstrained fn verify_unconstrained(id: Field, state: Planet) -> bool {
        let stored_hash = self.storage.state_roots.at(id).read();
        if stored_hash == 0 {
            state == Planet::zero()
        } else {
            let computed_hash = poseidon2_hash(state.serialize());
            computed_hash == stored_hash
        }
    }

    #[external("utility")]
    unconstrained fn compute_state_hash_unconstrained(state: Planet) -> Field {
        if (state == Planet::zero()) {
            0
        } else {
            poseidon2_hash(state.serialize())
        }
    }

    #[external("utility")]
    unconstrained fn get_state_root_unconstrained(id: Field) -> Field {
        self.storage.state_roots.at(id).read()
    }

    #[external("utility")]
    unconstrained fn get_default_planet_unconstrained() -> Planet {
        Planet::zero()
    }

    #[external("utility")]
    unconstrained fn get_admin_unconstrained() -> AztecAddress {
        self.storage.admin.read()
    }

    #[external("utility")]
    unconstrained fn get_authorized_count_unconstrained() -> u32 {
        self.storage.authorized_count.read()
    }

    #[external("utility")]
    unconstrained fn get_authorized_contract_unconstrained(index: u32) -> AztecAddress {
        self.storage.authorized_list.at(index).read()
    }

    #[external("utility")]
    unconstrained fn is_authorized_unconstrained(addr: AztecAddress) -> bool {
        let is_admin: bool = addr == self.storage.admin.read();
        let is_authorized: bool = self.storage.authorized_map.at(addr).read();
        is_admin | is_authorized
    }

    #[external("utility")]
    unconstrained fn is_initialized_unconstrained(id: Field) -> bool {
        let stored_hash = self.storage.state_roots.at(id).read();
        stored_hash != 0
    }

    // ================== PUBLIC VIEWS (AUTH) ==================

    #[external("public")]
    #[view]
    fn get_authorized_count() -> u32 {
        self.storage.authorized_count.read()
    }

    #[external("public")]
    #[view]
    fn get_authorized_contract(index: u32) -> AztecAddress {
        self.storage.authorized_list.at(index).read()
    }

    #[external("public")]
    #[view]
    fn is_authorized(addr: AztecAddress) -> bool {
        let is_admin: bool = addr == self.storage.admin.read();
        let is_authorized: bool = self.storage.authorized_map.at(addr).read();
        is_admin | is_authorized
    }
}
