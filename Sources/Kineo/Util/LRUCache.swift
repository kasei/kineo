//
//  LRUCache.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/17/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

class LinkedListNode<K : protocol<Equatable, Hashable>, V> {
    var next : LinkedListNode<K,V>?
    weak var previous : LinkedListNode<K,V>?
    var key : K
    var value : V
    init(key : K, value : V, next : LinkedListNode<K,V>?, previous : LinkedListNode<K,V>?) {
        self.key = key
        self.value = value
        self.next = next
        self.previous = previous
    }
}

class LinkedList<K : protocol<Equatable, Hashable>, V> : Sequence {
    var head : LinkedListNode<K,V>?
    weak var tail : LinkedListNode<K,V>?
    var count : Int
    
    init() {
        count = 0
        head = nil
        tail = nil
    }
    
    func append(key : K, value : V) -> LinkedListNode<K,V> {
        count += 1
        switch (head, tail) {
        case (_, .none):
            head = LinkedListNode(key: key, value: value, next: nil, previous: nil)
            tail = head
        case (_, .some(let t)):
            let node = LinkedListNode(key: key, value: value, next: nil, previous: t)
            t.next = node
            tail = node
        }
        return tail!
    }
    
    func prepend(node : LinkedListNode<K,V>) {
        count += 1
        switch (head, tail) {
        case (.none, _):
            node.next = nil
            node.previous = nil
            head = node
            tail = head
        case (.some(let h), _):
            node.next = h
            node.previous = nil
            h.previous = node
            head = node
        }
    }
    
    func prepend(key : K, value : V) -> LinkedListNode<K,V> {
        count += 1
        switch (head, tail) {
        case (.none, _):
            head = LinkedListNode(key: key, value: value, next: nil, previous: nil)
            tail = head
        case (.some(let h), _):
            let node = LinkedListNode(key: key, value: value, next: h, previous: nil)
            h.previous = node
            head = node
        }
        return head!
    }
    
    func removeLast() -> LinkedListNode<K,V>? {
        switch tail {
        case .none:
            return nil
        case .some(let node):
            count -= 1
            if let p = node.previous {
                tail = p
                p.next = nil
            } else {
                head = nil
                tail = nil
            }
            return node
        }
    }
    
    func remove(node : LinkedListNode<K,V>) {
        count -= 1
        if node === head && node === tail {
            count = 0
            head = nil
            tail = nil
        } else if node === head {
            let n = node.next!
            head = n
            n.previous = nil
        } else if node === tail {
            let p = node.previous!
            tail = p
            p.next = nil
        } else {
            let p = node.previous!
            let n = node.next!
            p.next = n
            n.previous = p
        }
    }
    
    func makeIterator() -> AnyIterator<LinkedListNode<K,V>> {
        var current = head
        return AnyIterator {
            let v = current
            if current != nil {
                current = current?.next
            }
            return v
        }
    }
}

public class LRUCache<K : protocol<Equatable, Hashable>, V> : Sequence {
    var dict : [K:LinkedListNode<K,V>]
    public var capacity : Int
    var list = LinkedList<K,V>()
    
    var hit : Int
    var miss : Int
    
    public init(capacity : Int) {
        self.capacity = capacity
        self.dict = [K:LinkedListNode<K,V>]()
        self.hit = 0
        self.miss = 0
    }
    
//    deinit {
//        let total = Double(hit + miss)
//        if total > 0 {
//            let hr = 100.0 * Double(self.hit) / total
//            let mr = 100.0 * Double(self.miss) / total
//            print(String(format: "LRUCache hit: %d (%.1f%%)", hit, hr))
//            print(String(format: "LRUCache miss: %d (%.1f%%)", miss, mr))
//        }
//    }
    
    public func removeValue(forKey key: K) -> V? {
        if let node = dict[key] {
            list.remove(node: node)
            dict.removeValue(forKey: key)
            return node.value
        } else {
            return nil
        }
    }
    
    public subscript(key : K) -> V? {
        get {
            if let node = dict[key] {
                hit += 1
                list.remove(node: node)
                list.prepend(node: node)
                return node.value
            } else {
                miss += 1
                return nil
            }
        }
        
        set(newValue) {
            if let node = dict[key] {
                list.remove(node: node)
            }
            if let value = newValue {
                let node = list.prepend(key: key, value: value)
                dict[key] = node
            } else {
                dict.removeValue(forKey: key)
            }
            if list.count > capacity {
                if let node = list.removeLast() {
                    dict.removeValue(forKey: node.key)
                }
            }
        }
    }
    
    public func makeIterator() -> AnyIterator<(K,V)> {
        let i = list.makeIterator()
        return AnyIterator {
            if let node = i.next() {
                return (node.key, node.value)
            } else {
                return nil
            }
        }
    }
}
