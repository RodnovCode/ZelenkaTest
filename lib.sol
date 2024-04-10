// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Тестовое задание от Rodnov

// Доп.контракт, занимается всем, что касается владением контракта
contract Ownable {

    // Открытая переменная - хранит адрес владельца
    address public owner;

    // Событие передачи владения
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    // Модификатор, который разрешает использовать определенную функцию только владельцу
    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // Функция для владельца, позволяющая передать владение контрактом другому адресу
        function transferOwnership(address _owner) public virtual onlyOwner {
        if (_owner == address(0)) revert InvalidOwner();
        owner = _owner;
        emit OwnershipTransferred(msg.sender, _owner);
    }

    // Функция для владельца, позволяющая передать владение контрактом нулевому адресу (полный отказ от владения, навсегда)
    // Никто больше не сможет вызывать админские функции onlyOwner
    function revokeOwnership() public virtual onlyOwner {
        owner = address(0);
        emit OwnershipTransferred(msg.sender, address(0));
    }    

    // Конструктор - функция, которая вызывается во время деплоя контракта, вызывается только один раз
    // Назначает деплоера владельцем контракта, а так же вызывает событие смены владельца (с нулевого адреса, на адрес деплоера)
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    // Пользовательские ошибки
    error Unauthorized();
    error InvalidOwner();    
}

// Основной контракт нашей библиотеки
contract Lib is Ownable {

    // Переменные
    mapping (uint => uint) public bookPrice; // Переменная соответсвия, хранит цену определенной книги
    mapping (uint => address) public ownerOf; // Переменная соответсвия, хранит владельца определенной книги
    mapping (address => bool) public alreadyHave; // переменная соответсвия, хранит bool покупал уже адрес книгу или нет
    address lastUser; // Внутренняя переменная, которая хранит последнего вызывающего функции takeTheBook, потом этот адрес используется для создания хеша (повышает рандомизацию цены книги)
    uint public minted; // Переменная хранит количество созданных книг 
    uint public amountPurchasedBooks; // Переменная хранит количество проданных книг

    // Структура книги
    struct Book {
        uint id; // Айди книги
        uint price; // Цена книги
    }

    // Функция, которая вызывается только один раз при деплое контрактом, создает выбранное количество книг с рандомными ценами
    constructor (uint booksAmount) {
        createBooksWithRandomPr(booksAmount);
    }

    // Функция для владельца, позволяющая создать какое-то количество книг с рандомной ценой
    // Максимальная цена книги - 1 eth
    // Минимальная цена книги - 0.01 eth
    function createBooksWithRandomPr(uint amount) public onlyOwner {
        for (uint i; i < amount; i++) {
            uint price = ((uint(keccak256(abi.encodePacked(block.number, minted, block.timestamp, lastUser))) % 100) + 1) * 10**15;
            bookPrice[minted] = price;
            ownerOf[minted] = address(this);
            minted++;
        }
    }

    // Функция для владельца, позволяет создать какое то количество новых книг с выбранной ценой
    function createBookWithFixPrice(uint amount, uint price) external onlyOwner {
        for (uint i; i < amount; i++) {
            bookPrice[minted] = price;
            ownerOf[minted] = address(this);
            minted++;
        }
    }

    // Функция позволяющая купить книгу любому желающему, кроме тех, кто уже покупал книгу
    function takeTheBook(uint id) external payable {
        uint price = bookPrice[id]; //внутренняя переменная price - хранит цену выбранной книги
        uint amount = msg.value; //внутренняя переменная amount - хранит количество eth, которое отправил юзер
        address user = msg.sender; //внутренняя переменная user - хранит адрес человека, который вызвал эту функцию

        require(alreadyHave[user] == false, "Already have"); //провека - покупал ли юзер уже книгу?
        require(ownerOf[id] == address(this), "this book has already been purchased or nonexistent"); // проверка на возможность покупки книги (существует ли такая кинга, не продана ли она?)
        require(amount >= price, "The amount sent must equal or exceed the cost of the book"); // проверка, отправил ли человек достаточное количество eth для покупки?
        ownerOf[id] = user; //передача книги новому владельцу
        alreadyHave[user] = true; //занесение юзера в список купивших
        if (amount > price) { //если юзер скинул eth больше чем нужно, то
            uint residue = amount - price; //внутренняя переменная residue, разница между ценой книги и отправленной суммой
            (bool success, ) = user.call{value: residue}(""); //сдача отправляется обратно вызывающему
            require(success); //проверка на успешную отправку сдачи
        }
        lastUser = user; //переменная lastUser теперь хранит адрес прошлого купившего (переменная нужна для повышения рандомизации в функции создании книг с рандомной ценой)
        amountPurchasedBooks++; //количество проданных книг +1
        (bool success1, ) = owner.call{value: price}(""); //отправка eth за книгу владельцу контракта
        require(success1); //проверка на успешность отправки
    }

    // Функция позволяет получить полный список книг и их цены
    function getAllBooksPrices() external view returns (string memory) {
        string memory result = "";
        for (uint i = 0; i < minted; i++) {
            result = string(abi.encodePacked(result, uintToString(i), ": ", uintToString(bookPrice[i]), "\n\n"));
        }
    return result;
    }

    // Вспомогательная внутренняя функция, которая переводит числовое значение в текстовое 
    // К сожалению в солидити напряпую перевести uint в string невозможно, приходится играться с байтами
    function uintToString(uint v) internal pure returns (string memory) {
        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = bytes1(uint8(48 + remainder));
        }
        bytes memory s = new bytes(i);
        for (uint j = 0; j < i; j++) {
            s[j] = reversed[i - j - 1];
        }
        return string(s);
    }
}
/**
В солидити рандома нет, есть псевдорандом только, но под наши цели он годится

В функции создания книг с рандомными ценами, мы берем как можно больше переменных и создаем из них хеш
хеш переводим в число и берем его модуль, далее домножаем чтобы получить приемлимую цену
**/