#include "tree_insert_destructive.h"

Tree *createTreeNode(int n){
    
    Tree * newNode = (Tree*) malloc(sizeof(Tree));
    newNode->n = n;
    newNode->left  = NULL;
    newNode->right = NULL;

}

void treeInsertHelper(Tree *root, int value){
    
    //leaf case
    if (root->left == NULL && root->right == NULL){
        Tree * new = createTreeNode(value);
        //insert at the left of the root
        if(value < root->n){                       
            root->left = new;
        }
        //insert at the right of the root
        else{              
            root->right = new;
        }
    }
    //non leaf case
    else {
        //insert inside the left subtree
        if (value < root->n){
            //if left is NULL then insert at left
            if (root->left == NULL){
                Tree *new = createTreeNode(value); 
                root->left = new;                
            }
            else{
                treeInsertHelper(root->left, value);
            }            
        }
        //insert inside the right subtree
        else{
            //if right side is 
            if (root->right == NULL){
                Tree *new = createTreeNode(value);
                root->right = new;
            }
            else{
                treeInsertHelper(root->right, value);
            }
        }
    }
}



int sumTreeHelper(Tree *root){

    //leaf case
    if (root->left == NULL && root->right == NULL){
       return root->n;
    }
    //non leaf case
    else {
        if (root->left == NULL){
            return root->n + sumTreeHelper(root->right);                
        }
        else if (root->right == NULL){
            return root->n + sumTreeHelper(root->left);
        }
        else {
            return root->n + sumTreeHelper(root->left) + sumTreeHelper(root->right);
        }     
    }
}


int sumTree(Tree *root){

    if (root == NULL){
        return 0;
    }
    
    return sumTreeHelper(root);

}

Tree *treeInsert(Tree *root, int value){
    
    //case NULL
    if (root == NULL){
        Tree *new = createTreeNode(value);
        return new;
    }
    else {
        treeInsertHelper(root, value);
    }

    return root;  

}


Tree * findMinSuccessor(Tree *right){

    Tree * tmp = right;
    
    //keep traversing the left of the tree to get to the leftmost node in the tree, since we know that left most nodes are always going to be smaller that the root
    while(tmp != NULL && tmp->left != NULL){
        tmp = tmp->left;
    }

    return tmp;

}


Tree *treeDelete(Tree * root, int value){

    if (root == NULL){
        return root;
    }
    
    //go to the left subtree as the value to be deleted is less that the node's value
    if (root->n > value){
        root->left = treeDelete(root->left, value);
    }
    //go to the right subtree as the value to be deleted is more that the node's value
    else if (root->n < value){
        root->right = treeDelete(root->right, value);
    }
    //otherwise the value to be deleted is the value at the root
    else{

       //if there is no left subtree, then find minimum successor in right subtree
        if(root->left == NULL){
            
            Tree *replacement = root->right; 
            //now free this node as it can be deleted;
            free(root);
            return replacement;

        }
        else if (root->right == NULL){

            Tree * replacement = root->left;
            //now free this node as it can be deleted;
            free(root);
            return replacement;

        }
        else{
            //find the minimum successor
            Tree *minSuccessor = findMinSuccessor(root->right);
            
            //copy successor over to the root
            root->n = minSuccessor->n;

            //recursively delete the minSuccessor;
            root->right = treeDelete(root->right, root->n);

        }
        return root;        
    }
}


Tree *helper(int s, int e){

    if (e < s){
        return NULL;
    }
    else if (e == s){
        return createTreeNode(s);
    }
    else{
        int m = s + ((e - s) / 2);
        Tree *newNode  = createTreeNode(m);
        newNode->left  = helper(s, m - 1);
        newNode->right = helper(m + 1, e);

        return newNode;
    }

}


void printTreeHelper(Tree *root){

    if (root == NULL){
        printf(" Null ");
        return;
    }

    printf("( %d ", root->n);
    printTreeHelper(root->left);
    printTreeHelper(root->right);
    printf(")");

}

void printTree(Tree *root){

    printf("Printing the tree in pre-order\n");
    printTreeHelper(root);
    printf("\n");    
    
}

void freeTree(Tree *root){

    if (root == NULL){
        return;
    }

    freeTree(root->left);
    freeTree(root->right);
    free(root);

}

long int power(int base, int superscript){

    long int power = 1;

    for(int i = 0; i < superscript; i++){
        power *= base;
    }

    return power;

}


int main (int argc, char ** argv){

    if (argc < 3){
        printf("Error: Usage: ./a.out treeSize random-iterations\n");
        exit(1);
    }

    srand(time(NULL));

    long int sizeParam = atol(argv[1]);

    long int iterations = atol(argv[2]);

    long int totalNodes = power(2, sizeParam + 1) - 1;

    Tree *root = helper(0, totalNodes);

    printTree(root);

    for(int i=0; i < iterations; i++){
        
        int n = rand(); 
        int j = n % totalNodes;
        if(n % 2 == 0){
            root = treeInsert(root, j);  
        }
        else{
            root = treeDelete(root, j);
        }

        printTree(root);


    }

    //free memory
    freeTree(root);

}
