module ModAddr::FooTaskStore3 {
	friend ModAddr::FooTask3;

	use Std::ASCII;
	use Std::Vector;
	use Std::Errors;
  use AptosFramework::Table::{Self, Table};
	use ModAddr::FooTaskId3::{Self, TaskId};

	const ETASK_ID_DUPLICATED: u64 = 1;
	const ETASK_ID_NOT_FOUND: u64 = 2;
  const ETASK_STATE_NOT_ENABLED: u64 = 4;
  const ETASK_STATE_NOT_MATCHED: u64 = 5;

	struct TaskData has store {
		id: TaskId,
		state: u8,
		meta_data: ASCII::String
	}

	struct TaskStore has key {
		task_table: Table<TaskId, TaskData>,
	}

	struct TaskEnabled has key {
		task_id_list: vector<TaskId>,
	}

	struct TaskDisabled has key {
		task_id_list: vector<TaskId>,
	}

	public(friend) fun is_initialized(addr: address): bool {
		exists<TaskStore>(addr)
	}

	public(friend) fun initialize(account: &signer) {
		move_to(account, TaskStore {
      task_table: Table::new(),
    });
		move_to(account, TaskEnabled {
		  task_id_list: Vector::empty(),
		});
		move_to(account, TaskDisabled {
		  task_id_list: Vector::empty(),
		});
	}

	public(friend) fun task_add(task_id: TaskId, meta_data: ASCII::String)
	acquires TaskStore, TaskEnabled {
		let task_data = TaskData {
      id: task_id,
      state: 0u8, // published
      meta_data,
    };
		let publisher = FooTaskId3::publisher(&task_id);

		let task_table = &mut borrow_global_mut<TaskStore>(publisher).task_table;
    // assert not contains
    assert!(!Table::contains(task_table, task_id), Errors::internal(ETASK_ID_DUPLICATED));
    Table::add(task_table, copy task_id, task_data);
    on_task_add(&task_id);
	}

	public(friend) fun task_change_state(task_id: &TaskId, from: u8, to: u8, disable: bool)
  acquires TaskStore, TaskEnabled, TaskDisabled {
    // assert contains
		assert_task_contains(task_id, Errors::invalid_argument(ETASK_ID_NOT_FOUND));
		// assert enabled then return list_index
		let (list_index_1, list_index_2) = assert_task_enabled(task_id, Errors::invalid_argument(ETASK_STATE_NOT_ENABLED));

		// ----->> remove from enabled
		if (disable) {
			remove_enabled(task_id, list_index_1, list_index_2);
		};

		// assert state == `from` then change to `to`
	  assert_and_change_task_state(task_id, from, to);

	  // ----->> insert to disabled
    if (disable) {
			insert_disabled(task_id);
    };
	}

	public(friend) fun task_state(task_id: &TaskId): u8 acquires TaskStore {
		// assert contains
		assert_task_contains(task_id, Errors::invalid_argument(ETASK_ID_NOT_FOUND));

		let publisher = FooTaskId3::publisher(task_id);
		let task_table = & borrow_global<TaskStore>(publisher).task_table;
		*&Table::borrow(task_table, *task_id).state
	}

	// --------------------------------------------------------------------------------------------

  fun assert_task_contains(task_id: &TaskId, error_code: u64) acquires TaskStore {
    let publisher = FooTaskId3::publisher(task_id);
    let task_table = & borrow_global<TaskStore>(publisher).task_table;
    assert!(
      Table::contains(task_table, *task_id),
			error_code
    );
  }

  fun assert_task_enabled(task_id: &TaskId, error_code: u64): (u64, u64)
  acquires TaskEnabled {
    let (publisher, performer) = FooTaskId3::addresses_of(task_id);

    let task_id_list = & borrow_global<TaskEnabled>(publisher).task_id_list;
    let (is_exist, list_index_1) = Vector::index_of(task_id_list, task_id);
    assert!(is_exist, error_code);

    let task_id_list = & borrow_global<TaskEnabled>(performer).task_id_list;
    let (is_exist, list_index_2) = Vector::index_of(task_id_list, task_id);
    assert!(is_exist, error_code);

    (list_index_1, list_index_2)
  }

  fun assert_and_change_task_state(task_id: &TaskId, from: u8, to: u8) acquires TaskStore {
		let publisher = FooTaskId3::publisher(task_id);
		let task_table = &mut borrow_global_mut<TaskStore>(publisher).task_table;
  	let task_data = Table::borrow_mut<TaskId, TaskData>(task_table, *task_id);
		// assert state == from
    assert!(task_data.state==from, Errors::invalid_state(ETASK_STATE_NOT_MATCHED));
  	task_data.state = to;
  }

  fun remove_enabled(task_id: &TaskId, task_index_1: u64, task_index_2: u64) acquires TaskEnabled {
    let (publisher, performer) = FooTaskId3::addresses_of(task_id);

		let task_id_list = &mut borrow_global_mut<TaskEnabled>(publisher).task_id_list;
		Vector::remove(task_id_list, task_index_1);

		let task_id_list = &mut borrow_global_mut<TaskEnabled>(performer).task_id_list;
		Vector::remove(task_id_list, task_index_2);
  }

  fun insert_disabled(task_id: &TaskId) acquires TaskDisabled {
    let (publisher, performer) = FooTaskId3::addresses_of(task_id);

		let task_id_list = &mut borrow_global_mut<TaskDisabled>(publisher).task_id_list;
		Vector::push_back(task_id_list, *task_id);

		let task_id_list = &mut borrow_global_mut<TaskDisabled>(performer).task_id_list;
		Vector::push_back(task_id_list, *task_id);
  }

  fun on_task_add(task_id: &TaskId) acquires TaskEnabled {
    let (publisher, performer) = FooTaskId3::addresses_of(task_id);
    // insert to list & emit event
		let store = borrow_global_mut<TaskEnabled>(publisher);
		Vector::push_back(&mut store.task_id_list, *task_id);
		let store = borrow_global_mut<TaskEnabled>(performer);
		Vector::push_back(&mut store.task_id_list, *task_id);
  }

}
