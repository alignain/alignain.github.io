
#' ---
#' title: "DIY I"
#' author: "Md Zulquar Nain"
#' date: "`r Sys.Date()`"
#' ---



# Compute √(4+12)/√(2+2)

x1 <- sqrt(4+12)/sqrt(2+2) 
# We have computed and stored it in the object x1 and to print
# just type the name of the object
x1

#Create a vector named y which must contain 6 elements
#Create a vector using three different methods

# We can create a vector using following three methods

x2 <- c(1,2,3,4,5,6)
x3 <- seq(1:6)
x4 <- rep(1:6)

# You can print these vectors
x2
x3
x4

# Create a vector in descending order from 10 to 1 in steps of
# 0.5 and add an element to the vector

x5 <- seq(from=10, to=1, by=-0.5)
x6 <- seq(10,1,-0.5)

# Find the length, maximum and minimum of the vector

length(x5)
max(x5)
min(x5)

# Create a vector of heights of five people sitting around you.

# Height measured in centimeters 
h1 <- c(70,102,75,80,100)

# Change the value of the first and last elements of the above vector.
# To asses a specific element, we use [], what we call indexing of a 
#vector

# For example, here we are accessing the first element and changing
# it to 80
h1[1] <- 80
h1

# Change the last one
h1[5] <- 120
h1

#Find the sum and product of first 20 natural numbers

#First create a vector of first 20 natural numbers then use the
# function sum and prod

nvec <- seq(1:20)

S <- sum(nvec)
P <- prod(nvec)

# To print the result we can use the function paste
paste("The sum of first 20 natural numbers is", S)
paste("The product of first 20 natural numbers is", P)

# Create a matrix of two columns and two row using cbind rbind

# First create two vectors

r1 <- c(2,3)
r2 <- c(7,8)

# creating the matrix using cbind
m1 <- cbind(r1,r2)
m1

# creating the matrix using rbind
m2 <- rbind(r1,r2)
m2


# Generate a third column by adding the first TWO columns
r3 <- m1[,1]+m1[,2]
# creating the matrix
m3 <- cbind(m1,r3)
m3

# Create a character vector

cvec <- c("name1","name2","4")

#to check the type of the vector we use the function typeof

typeof(cvec)


# Create a vector of categorical data
categories <- factor(c("High", "Medium", "Low", "High", "Low", "Medium"))

# Print the vector
print(categories)

# Check levels of the categorical variable
print(levels(categories))

