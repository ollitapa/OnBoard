extension AsyncStorage {

    /// Creates a cache that is combined with given store.
    /// This means:
    ///    - Changes to this store are pushed to backing cache
    ///    - `value(for:)` first checks this cache for values and if not found
    ///      it'll search the backing storage. Returned value from the backing storage will be saved to
    ///      default storage for later access.
    public func combined<Storage: AsyncStorage>(
        with storage: Storage
    ) -> CombinedStorage<Self, Storage>
    where Storage.Value == Value, Storage.Id == Id {
        CombinedStorage(defaultStorage: self, backup: storage)
    }
}

public struct CombinedStorage<DefaultStorage: AsyncStorage, BackupStorage: AsyncStorage>: AsyncStorage
where DefaultStorage.Value == BackupStorage.Value, DefaultStorage.Id == BackupStorage.Id {

    public typealias Id = BackupStorage.Id
    public typealias Value = BackupStorage.Value

    let defaultStorage: DefaultStorage
    let backup: BackupStorage

    init(defaultStorage: DefaultStorage, backup: BackupStorage) {
        self.defaultStorage = defaultStorage
        self.backup = backup
    }

    public func value(for id: Id) async throws -> Value? {
        // Try if we have a value already
        if let value = try await defaultStorage.value(for: id) {
            // Return found value, no need to check backing store
            return value
        } else {
            // No value found, try backing store
            if let value = try await backup.value(for: id) {
                // We got a value, store it to self and return to original caller
                try await defaultStorage.saveValue(value, for: id)
                return value
            } else {
                return nil
            }
        }
    }


    public func saveValue(_ value: Value?, for id: Id) async throws {
        // We need to get the old value if saving new fails, we need to be able to revert changes.
        let oldValue = try await backup.value(for: id)

        try await backup.saveValue(value, for: id)

        do {
            try await defaultStorage.saveValue(value, for: id)
        } catch {
            // Because source cache failed, we need to reset the destination with old value and
            // then after that fail the whole chain
            try await backup.saveValue(oldValue, for: id)
            throw error
        }
    }
}
